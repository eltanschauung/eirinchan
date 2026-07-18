defmodule Eirinchan.ThreadWatcherTest do
  use Eirinchan.DataCase, async: true
  import Ecto.Query, only: [from: 2]

  alias Eirinchan.PostOwnership
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Repo
  alias Eirinchan.ThreadWatcher
  alias Eirinchan.ThreadWatcher.Watch

  test "watch_thread upserts and watched_thread_ids batches" do
    board = board_fixture(%{uri: "watchbatch", title: "Watch Batch"})
    first_thread = thread_fixture(board, %{body: "First"})
    second_thread = thread_fixture(board, %{body: "Second"})
    token = "token-1234567890123456"

    assert {:ok, watch} = ThreadWatcher.watch_thread(token, board.uri, first_thread.id)
    assert watch.browser_token == Eirinchan.BrowserIdentity.reference(token)
    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, board.uri, second_thread.id)
    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, board.uri, first_thread.id)

    assert MapSet.new([first_thread.id, second_thread.id]) ==
             ThreadWatcher.watched_thread_ids(token, board.uri)
  end

  test "watch_thread enforces a per-browser storage cap while allowing upserts" do
    board = board_fixture(%{uri: "watchcap", title: "Watch Cap"})
    first_thread = thread_fixture(board, %{body: "First"})
    second_thread = thread_fixture(board, %{body: "Second"})
    token = "token-cap-123456789012"

    assert {:ok, _watch} =
             ThreadWatcher.watch_thread(token, board.uri, first_thread.id, %{}, max_threads: 1)

    assert {:ok, _watch} =
             ThreadWatcher.watch_thread(token, board.uri, first_thread.id, %{}, max_threads: 1)

    assert {:error, :watch_limit} =
             ThreadWatcher.watch_thread(token, board.uri, second_thread.id, %{}, max_threads: 1)

    assert ThreadWatcher.watch_count(token) == 1
  end

  test "mark_seen updates last_seen_post_id" do
    board = board_fixture(%{uri: "watchseenctx", title: "Watch Seen"})
    thread = thread_fixture(board, %{body: "OP"})
    reply = reply_fixture(board, thread, %{body: "Reply"})
    token = "token-seen-1234567890"

    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, board.uri, thread.id)
    assert {:ok, watch} = ThreadWatcher.mark_seen(token, board.uri, thread.id, reply.id)
    assert watch.last_seen_post_id == reply.id
  end

  test "mark_seen does not create a watch for untracked threads" do
    board = board_fixture(%{uri: "watchmissing", title: "Watch Missing"})
    thread = thread_fixture(board, %{body: "OP"})

    assert {:ok, nil} =
             ThreadWatcher.mark_seen(
               "token-missing-1234567890",
               board.uri,
               thread.id,
               thread.id
             )

    refute ThreadWatcher.watched?("token-missing-1234567890", board.uri, thread.id)
  end

  test "unwatch_thread removes one watch" do
    board = board_fixture(%{uri: "watchremove", title: "Watch Remove"})
    thread = thread_fixture(board, %{body: "OP"})
    token = "token-remove-1234567890"

    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, board.uri, thread.id)
    assert {:ok, 1} = ThreadWatcher.unwatch_thread(token, board.uri, thread.id)
    refute ThreadWatcher.watched?(token, board.uri, thread.id)
  end

  test "watch_state_for_board returns unread counts and watch_count totals" do
    board = board_fixture(%{uri: "watchstate", title: "Watch State"})
    thread = thread_fixture(board, %{body: "OP"})
    reply1 = reply_fixture(board, thread, %{body: "Reply one"})
    _reply2 = reply_fixture(board, thread, %{body: "Reply two"})

    assert {:ok, _watch} =
             ThreadWatcher.watch_thread("token-state-1234567890", board.uri, thread.id, %{
               last_seen_post_id: reply1.id
             })

    expected_last_seen = PublicIds.public_id(reply1)
    state = ThreadWatcher.watch_state_for_board("token-state-1234567890", board.uri)

    assert %{watched: true, unread_count: 1, last_seen_post_id: ^expected_last_seen} =
             state[PublicIds.public_id(thread)]

    assert ThreadWatcher.watch_count("token-state-1234567890") == 1
  end

  test "watch metrics include unread watched posts separately from (You) replies" do
    board = board_fixture(%{uri: "watchyou", title: "Watch You"})
    thread = thread_fixture(board, %{body: "OP"})
    owned_reply = reply_fixture(board, thread, %{body: "Owned reply"})
    _plain_reply = reply_fixture(board, thread, %{body: "plain unread"})

    _citing_reply =
      reply_fixture(board, thread, %{body: ">>#{PublicIds.public_id(owned_reply)} cited"})

    token = "token-you-1234567890"

    assert {:ok, _} = PostOwnership.record(token, owned_reply.id)

    assert {:ok, _watch} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id, %{
               last_seen_post_id: owned_reply.id
             })

    snapshot = ThreadWatcher.snapshot(token, summaries: true)

    assert %{watcher_count: 1, watcher_unread_count: 2, watcher_you_count: 1} =
             snapshot.metrics

    assert %{you_unread_count: 1} =
             snapshot.watch_state_by_board[board.uri][PublicIds.public_id(thread)]

    [summary] = snapshot.summaries
    assert summary.you_unread_count == 1
    assert summary.you_unread_post_id
    assert summary.last_post_id == PublicIds.public_id(List.last(Repo.all(from_post(thread.id))))
  end

  test "watch_thread rejects a last-seen post from another thread" do
    board = board_fixture(%{uri: "watchseenscope", title: "Watch Seen Scope"})
    watched_thread = thread_fixture(board, %{body: "Watched"})
    other_thread = thread_fixture(board, %{body: "Other"})
    other_reply = reply_fixture(board, other_thread, %{body: "Other reply"})
    token = "token-invalid-seen-1234"

    assert {:error, :invalid_last_seen_post} =
             ThreadWatcher.watch_thread(token, board.uri, watched_thread.id, %{
               last_seen_post_id: other_reply.id
             })

    refute ThreadWatcher.watched?(token, board.uri, watched_thread.id)
  end

  test "seen high-water marks never move backwards" do
    board = board_fixture(%{uri: "watchhighwater", title: "Watch High Water"})
    thread = thread_fixture(board, %{body: "OP"})
    first_reply = reply_fixture(board, thread, %{body: "First"})
    second_reply = reply_fixture(board, thread, %{body: "Second"})
    token = "token-high-water-12345"

    assert {:ok, watch} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id, %{
               last_seen_post_id: second_reply.id
             })

    assert watch.last_seen_post_id == second_reply.id

    assert {:ok, watch} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id, %{
               last_seen_post_id: first_reply.id
             })

    assert watch.last_seen_post_id == second_reply.id

    assert {:ok, watch} =
             ThreadWatcher.mark_seen(token, board.uri, thread.id, first_reply.id)

    assert watch.last_seen_post_id == second_reply.id
  end

  test "a watch follows a thread moved to another board without duplication" do
    source_board = board_fixture(%{uri: "watchsource", title: "Watch Source"})
    target_board = board_fixture(%{uri: "watchtarget", title: "Watch Target"})
    thread = thread_fixture(source_board, %{body: "Moving"})
    token = "token-moved-123456789"

    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, source_board.uri, thread.id)

    thread
    |> Ecto.Changeset.change(board_id: target_board.id, public_id: 77)
    |> Repo.update!()

    assert ThreadWatcher.watch_state_for_board(token, source_board.uri) == %{}

    assert %{77 => %{watched: true}} =
             ThreadWatcher.watch_state_for_board(token, target_board.uri)

    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, target_board.uri, thread.id)
    assert ThreadWatcher.watch_count(token) == 1

    assert [%Watch{board_uri: "watchtarget"}] = ThreadWatcher.list_watches(token)
  end

  test "deleting a watched thread cascades the watch" do
    board = board_fixture(%{uri: "watchcascade", title: "Watch Cascade"})
    thread = thread_fixture(board, %{body: "OP"})
    token = "token-cascade-1234567"

    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, board.uri, thread.id)
    assert ThreadWatcher.watch_count(token) == 1

    Repo.delete!(thread)

    assert ThreadWatcher.watch_count(token) == 0
    assert ThreadWatcher.list_watch_summaries(token) == []
  end

  test "latent watches stay out of every visible watcher projection" do
    board = board_fixture(%{uri: "watchlatent", title: "Latent Watch"})
    thread = thread_fixture(board, %{body: "OP"})
    reply = reply_fixture(board, thread, %{body: "Owned reply"})
    token = "token-latent-123456789"

    assert {:ok, %Watch{activated: false}} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id, %{
               last_seen_post_id: reply.id,
               activated: false
             })

    assert ThreadWatcher.watched?(token, board.uri, thread.id)
    assert ThreadWatcher.watch_count(token) == 0

    assert ThreadWatcher.watch_metrics(token) == %{
             watcher_count: 0,
             watcher_unread_count: 0,
             watcher_you_count: 0
           }

    assert ThreadWatcher.watch_state_for_board(token, board.uri) == %{}
    assert ThreadWatcher.list_watch_summaries(token) == []
  end

  test "a later reply activates other browsers' latent watches only" do
    board = board_fixture(%{uri: "watchactivate", title: "Activate Watch"})
    thread = thread_fixture(board, %{body: "OP"})
    first_reply = reply_fixture(board, thread, %{body: "First reply"})
    posting_token = "token-posting-12345678"
    waiting_token = "token-waiting-12345678"

    for token <- [posting_token, waiting_token] do
      assert {:ok, %Watch{activated: false}} =
               ThreadWatcher.watch_thread(token, board.uri, thread.id, %{
                 last_seen_post_id: first_reply.id,
                 activated: false
               })
    end

    _later_reply = reply_fixture(board, thread, %{body: "Later reply"})

    assert {:ok, 1} = ThreadWatcher.activate_for_reply(thread.id, posting_token)
    assert ThreadWatcher.watch_count(posting_token) == 0

    assert %{watcher_count: 1, watcher_unread_count: 1} =
             ThreadWatcher.watch_metrics(waiting_token)
  end

  test "explicitly watching upgrades an existing latent watch" do
    board = board_fixture(%{uri: "watchupgrade", title: "Upgrade Watch"})
    thread = thread_fixture(board, %{body: "OP"})
    token = "token-upgrade-1234567"

    assert {:ok, %Watch{activated: false}} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id, %{activated: false})

    assert {:ok, %Watch{activated: true}} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id)

    assert ThreadWatcher.watch_count(token) == 1
  end

  defp from_post(thread_id) do
    from(post in Post,
      where: post.id == ^thread_id or post.thread_id == ^thread_id,
      order_by: [asc: post.id]
    )
  end
end
