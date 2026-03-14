defmodule EirinchanWeb.ThreadWatcherControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.Posts.PublicIds

  alias Eirinchan.ThreadWatcher
  alias Plug.CSRFProtection

  test "watches and unwatches a thread with browser token", %{conn: conn} do
    board = board_fixture(%{uri: "watch", title: "Watch"})
    thread = thread_fixture(board, %{body: "Watch me"})
    token = "token-1234567890123456"
    thread_id = PublicIds.public_id(thread)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> post("/watcher/#{board.uri}/#{PublicIds.public_id(thread)}", %{
        "_csrf_token" => CSRFProtection.get_csrf_token()
      })

    assert %{
             "ok" => true,
             "watched" => true,
             "thread_id" => ^thread_id,
             "watcher_count" => 1,
             "watcher_unread_count" => 0,
             "watcher_you_count" => 0
           } = json_response(conn, 200)

    assert ThreadWatcher.watched?(token, board.uri, thread.id)

    conn =
      build_conn()
      |> put_req_cookie("browser_token", token)
      |> put_req_header("x-csrf-token", CSRFProtection.get_csrf_token())
      |> delete("/watcher/#{board.uri}/#{thread_id}")

    assert %{
             "ok" => true,
             "watched" => false,
             "thread_id" => ^thread_id,
             "watcher_count" => 0,
             "watcher_unread_count" => 0,
             "watcher_you_count" => 0
           } = json_response(conn, 200)

    refute ThreadWatcher.watched?(token, board.uri, thread.id)
  end

  test "returns not found for reply ids", %{conn: conn} do
    board = board_fixture(%{uri: "watch404", title: "Watch 404"})
    thread = thread_fixture(board, %{body: "OP"})
    reply = reply_fixture(board, thread, %{body: "Reply"})

    conn =
      conn
      |> put_req_cookie("browser_token", "token-1234567890123456")
      |> post("/watcher/#{board.uri}/#{PublicIds.public_id(reply)}", %{
        "_csrf_token" => CSRFProtection.get_csrf_token()
      })

    assert response(conn, 404)
  end

  test "marks watched thread as seen", %{conn: conn} do
    board = board_fixture(%{uri: "watchseen", title: "Watch Seen"})
    thread = thread_fixture(board, %{body: "Watch me"})
    token = "token-abcdef1234567890"
    thread_id = PublicIds.public_id(thread)

    {:ok, _watch} =
      ThreadWatcher.watch_thread(token, board.uri, thread.id, %{last_seen_post_id: thread.id})

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_header("x-csrf-token", CSRFProtection.get_csrf_token())
      |> patch("/watcher/#{board.uri}/#{thread_id}", %{
        "last_seen_post_id" => Integer.to_string(thread_id)
      })

    assert %{
             "ok" => true,
             "thread_id" => ^thread_id,
             "last_seen_post_id" => last_seen_post_id,
             "watcher_count" => 1,
             "watcher_unread_count" => 0,
             "watcher_you_count" => 0
           } = json_response(conn, 200)

    assert last_seen_post_id == thread_id
  end
end
