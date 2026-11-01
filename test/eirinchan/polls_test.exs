defmodule Eirinchan.PollsTest do
  use Eirinchan.DataCase, async: false
  alias Eirinchan.{BrowserIdentity, Polls, Posts}
  alias Eirinchan.Antispam.SearchQuery
  alias Eirinchan.Polls.Vote
  alias Eirinchan.Posts.{Post, Persistence}
  alias Eirinchan.Runtime.Config

  defp config(board) do
    Config.compose(
      nil,
      %{},
      Map.merge(board.config_overrides, %{
        generation_strategy: "build_on_load",
        flood_time: 0,
        filters: [],
        flood_ip_count: 0,
        flood_browser_count: 0,
        flood_global_count: 0
      }),
      request_host: "example.test"
    )
  end

  defp identity(ip \\ {192, 0, 2, 25}, browser \\ "synthetic-poll-browser"),
    do: %{remote_ip: ip, browser_ref: BrowserIdentity.reference(browser)}

  defp create_poll(board, question \\ "Meaning of life?", request \\ identity()) do
    Posts.create_public_post(
      board,
      %{
        "body" => "Before\n/poll \"#{question}\" \"First option\" second third\nAfter",
        "post" => "New Topic"
      },
      config: config(board),
      request: Map.put(request, :referer, "http://example.test/#{board.uri}/index.html")
    )
  end

  test "a poll is an ordinary post with retained surrounding text and derived fields" do
    board = board_fixture()
    assert {:ok, post, _} = create_poll(board)
    assert post.body =~ "Before\n/poll"
    assert post.body =~ "\nAfter"
    assert post.poll_question == "Meaning of life?"
    assert post.poll_options == ["First option", "second", "third"]
    assert {:ok, reloaded} = Posts.get_post(board, post.public_id)
    assert reloaded.poll_question == post.poll_question
  end

  test "a poll can be a reply as well as a thread" do
    board = board_fixture()
    thread = thread_fixture(board)

    assert {:ok, reply, _} =
             Posts.create_public_post(
               board,
               %{
                 "body" => "/poll Q a b",
                 "thread" => to_string(thread.public_id),
                 "post" => "New Reply"
               },
               config: config(board),
               request:
                 Map.put(identity(), :referer, "http://example.test/#{board.uri}/index.html")
             )

    assert reply.thread_id == thread.id
    assert reply.poll_options == ["a", "b"]
  end

  test "two creations per rolling hour cover all boards and survive deletion" do
    a = board_fixture()
    b = board_fixture()
    assert {:ok, first, _} = create_poll(a, "First?")
    assert {:ok, _, _} = create_poll(b, "Second?")
    assert {:ok, _} = Posts.moderate_delete_post(a, first.public_id, config: config(a))
    assert {:error, :poll_rate_limited} = create_poll(a, "Third?")
    assert Repo.aggregate(from(q in SearchQuery, where: q.activity == "poll_create"), :count) == 2

    Repo.update_all(from(q in SearchQuery, where: q.activity == "poll_create"),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -3601, :second)]
    )

    assert {:ok, _, _} = create_poll(a, "New hour?")
  end

  test "changing only IP or only browser cannot evade creation limits" do
    board = board_fixture()
    assert {:ok, _, _} = create_poll(board, "First?")
    assert {:ok, _, _} = create_poll(board, "Second?")

    assert {:error, :poll_rate_limited} =
             create_poll(board, "Third?", identity({198, 51, 100, 25}))

    assert {:error, :poll_rate_limited} =
             create_poll(board, "Fourth?", identity({192, 0, 2, 25}, "other-browser"))

    assert {:ok, _, _} =
             create_poll(
               board,
               "Independent?",
               identity({203, 0, 113, 25}, "independent-browser")
             )
  end

  test "IP nulling does not bypass the creation quota or prevent private voting receipts" do
    board = board_fixture(%{config_overrides: %{ip_nulling: true}})
    assert {:ok, first, _} = create_poll(board, "First?")
    assert first.ip_subnet == nil
    assert {:ok, _, _} = create_poll(board, "Second?")
    assert {:error, :poll_rate_limited} = create_poll(board, "Third?")
    assert {:ok, %{voted: true, total: 1}} = Polls.vote(first.id, 0, identity())
  end

  test "failed post insertion rolls back the poll allowance and public ID allocation" do
    board = board_fixture()
    assert {:ok, attrs} = Polls.attach(%{"body" => "/poll Q a b", "ip_subnet" => "192.0.2.25"})

    assert {:error, :forced_failure} =
             Persistence.create_post_record(
               board,
               nil,
               attrs,
               identity(),
               Repo,
               config(board),
               DateTime.utc_now(),
               false,
               fn -> {:error, :forced_failure} end
             )

    assert Repo.aggregate(from(q in SearchQuery, where: q.activity == "poll_create"), :count) == 0
    assert Repo.aggregate(from(p in Post, where: p.board_id == ^board.id), :count) == 0

    assert Repo.get!(Eirinchan.Boards.BoardRecord, board.id).next_public_post_id ==
             board.next_public_post_id
  end

  test "forged metadata cannot create a poll or vote on a plain post" do
    board = board_fixture()

    assert {:ok, plain, _} =
             Posts.create_public_post(
               board,
               %{
                 "body" => "ordinary post",
                 "post" => "New Topic",
                 "poll_question" => "Forged?",
                 "poll_options" => ["a", "b"]
               },
               config: config(board),
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    assert plain.poll_question == nil
    assert plain.poll_options == []
    assert {:error, :not_found} = Polls.vote(plain.id, 0, identity())
  end

  test "results and total counts stay hidden until that identity has voted" do
    board = board_fixture()
    assert {:ok, post, _} = create_poll(board)
    assert Polls.states([post.id], identity()) == %{post.id => %{voted: false}}

    assert {:ok, %{voted: true, total: 1, results: [%{count: 0}, %{count: 1}, %{count: 0}]}} =
             Polls.vote(post.id, 1, identity())

    newcomer = identity({198, 51, 100, 30}, "newcomer")
    assert Polls.states([post.id], newcomer) == %{post.id => %{voted: false}}
    assert {:ok, %{total: 2}} = Polls.vote(post.id, 2, newcomer)
    assert %{voted: true, total: 2} = Polls.states([post.id], identity())[post.id]
  end

  test "duplicate votes are idempotent across IP/browser changes and cannot change choice" do
    board = board_fixture()
    assert {:ok, post, _} = create_poll(board)
    assert {:ok, %{total: 1}} = Polls.vote(post.id, 0, identity())

    for client <- [
          identity(),
          identity({192, 0, 2, 25}, "different"),
          identity({198, 51, 100, 25})
        ] do
      assert {:ok, %{total: 1, results: [%{count: 1}, %{count: 0}, %{count: 0}]}} =
               Polls.vote(post.id, 2, client)
    end

    assert Repo.aggregate(Vote, :count) == 1
    vote = Repo.one!(Vote)
    assert String.length(vote.ip_ref) == 43
    assert String.length(vote.browser_ref) == 43
    refute vote.ip_ref =~ "192.0.2"
    refute vote.browser_ref == identity().browser_ref
  end

  test "invalid choices and absent client addresses do not create votes" do
    board = board_fixture()
    assert {:ok, post, _} = create_poll(board)

    for choice <- [-1, 3, 6, "0", nil] do
      assert {:error, :invalid_choice} = Polls.vote(post.id, choice, identity())
    end

    assert {:error, :poll_identity_required} = Polls.vote(post.id, 0, %{})
    assert Repo.aggregate(Vote, :count) == 0
  end

  test "IPv4 mapped addresses use the same private receipt" do
    board = board_fixture()
    assert {:ok, post, _} = create_poll(board)
    assert {:ok, %{total: 1}} = Polls.vote(post.id, 0, %{remote_ip: "::ffff:192.0.2.25"})
    assert {:ok, %{total: 1}} = Polls.vote(post.id, 1, %{remote_ip: {192, 0, 2, 25}})
  end

  test "surrounding text can be edited but a live poll cannot be changed or removed" do
    board = board_fixture()
    assert {:ok, post, _} = create_poll(board)
    edited = "New preface\n/poll \"Meaning of life?\" \"First option\" second third\nNew end"

    assert {:ok, updated} =
             Posts.update_post(board, post.public_id, %{"body" => edited}, config: config(board))

    assert updated.body == edited

    for body <- [
          "No poll",
          "/poll Q a b",
          "/poll \"Meaning of life?\" \"First option\" second changed"
        ] do
      assert {:error, %Ecto.Changeset{}} =
               Posts.update_post(board, post.public_id, %{"body" => body}, config: config(board))
    end

    assert Repo.get!(Post, post.id).body == edited
  end

  test "votes follow a moved thread and cascade away when the post is deleted" do
    a = board_fixture()
    b = board_fixture()
    assert {:ok, post, _} = create_poll(a)
    assert {:ok, %{total: 1}} = Polls.vote(post.id, 1, identity())

    assert {:ok, moved} =
             Posts.move_thread(a, post.public_id, b,
               source_config: config(a),
               target_config: config(b)
             )

    assert moved.poll_question == post.poll_question
    assert %{voted: true, total: 1} = Polls.states([moved.id], identity())[moved.id]
    assert {:ok, _} = Posts.moderate_delete_post(b, moved.public_id, config: config(b))
    assert Repo.aggregate(Vote, :count) == 0
    assert Polls.states([post.id], identity()) == %{}
  end

  test "static pages include the same voting assets as dynamic pages" do
    board = board_fixture()
    assert {:ok, post, _} = create_poll(board)
    assert :ok = Eirinchan.Build.build_thread(board, post.id, config: config(board))
    assert :ok = Eirinchan.Build.build_indexes(board, config: config(board))

    for file <- ["index.html", "catalog.html", "res/#{post.public_id}.html"] do
      html = File.read!(Path.join([Eirinchan.Build.board_root(), board.uri, file]))
      assert html =~ "/js/polls.js"
      assert html =~ "/stylesheets/polls.css"
      refute html =~ "Total votes:"
    end
  end

  test "HTML is escaped, preserves line order and never embeds private results in cached fragments" do
    board = board_fixture()
    assert {:ok, post, _} = create_poll(board, "<script>alert(1)</script>?")
    html = EirinchanWeb.PostView.body_html(post, board, post, config(board))
    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"
    refute html =~ "/poll"
    assert html =~ "Before<br/>"
    assert html =~ "<br/>After"
    assert html =~ ~s(type="button" class="poll-vote")
    refute html =~ "<form"
    refute html =~ "Total votes"
    assert {:ok, _} = Polls.vote(post.id, 0, identity())
    assert EirinchanWeb.PostView.body_html(post, board, post, config(board)) == html
  end
end
