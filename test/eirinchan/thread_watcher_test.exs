defmodule Eirinchan.ThreadWatcherTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.ThreadWatcher
  alias Eirinchan.PostOwnership

  test "watch_thread upserts and watched_thread_ids batches" do
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 10)
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 11)
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 10)

    assert MapSet.new([10, 11]) ==
             ThreadWatcher.watched_thread_ids("token-1234567890123456", "bant")
  end

  test "mark_seen updates last_seen_post_id" do
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 12)
    assert {:ok, watch} = ThreadWatcher.mark_seen("token-1234567890123456", "bant", 12, 99)
    assert watch.last_seen_post_id == 99
  end

  test "mark_seen does not create a watch for untracked threads" do
    assert {:ok, nil} = ThreadWatcher.mark_seen("token-1234567890123456", "bant", 999, 1000)
    refute ThreadWatcher.watched?("token-1234567890123456", "bant", 999)
  end

  test "unwatch_thread removes one watch" do
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 13)
    assert {:ok, 1} = ThreadWatcher.unwatch_thread("token-1234567890123456", "bant", 13)
    refute ThreadWatcher.watched?("token-1234567890123456", "bant", 13)
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

  test "watch metrics include unread (You) replies" do
    board = board_fixture(%{uri: "watchyou", title: "Watch You"})
    thread = thread_fixture(board, %{body: "OP"})
    owned_reply = reply_fixture(board, thread, %{body: "Owned reply"})
    _citing_reply = reply_fixture(board, thread, %{body: ">>#{PublicIds.public_id(owned_reply)} cited"})
    token = "token-you-1234567890"

    assert {:ok, _} = PostOwnership.record(token, owned_reply.id)

    assert {:ok, _watch} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id, %{
               last_seen_post_id: owned_reply.id
             })

    assert %{watcher_count: 1, watcher_you_count: 1} = ThreadWatcher.watch_metrics(token)

    state = ThreadWatcher.watch_state_for_board(token, board.uri)
    assert %{you_unread_count: 1} = state[PublicIds.public_id(thread)]

    [summary] = ThreadWatcher.list_watch_summaries(token)
    assert summary.you_unread_count == 1
  end
end
