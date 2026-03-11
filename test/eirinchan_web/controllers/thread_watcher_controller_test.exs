defmodule EirinchanWeb.ThreadWatcherControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.ThreadWatcher
  alias Plug.CSRFProtection

  test "watches and unwatches a thread with browser token", %{conn: conn} do
    board = board_fixture(%{uri: "watch", title: "Watch"})
    thread = thread_fixture(board, %{body: "Watch me"})
    token = "token-1234567890123456"
    thread_id = thread.id

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> post("/watcher/#{board.uri}/#{thread.id}", %{"_csrf_token" => CSRFProtection.get_csrf_token()})

    assert %{"ok" => true, "watched" => true, "thread_id" => ^thread_id} = json_response(conn, 200)
    assert ThreadWatcher.watched?(token, board.uri, thread_id)

    conn =
      build_conn()
      |> put_req_cookie("browser_token", token)
      |> put_req_header("x-csrf-token", CSRFProtection.get_csrf_token())
      |> delete("/watcher/#{board.uri}/#{thread_id}")

    assert %{"ok" => true, "watched" => false, "thread_id" => ^thread_id} =
             json_response(conn, 200)

    refute ThreadWatcher.watched?(token, board.uri, thread_id)
  end

  test "returns not found for reply ids", %{conn: conn} do
    board = board_fixture(%{uri: "watch404", title: "Watch 404"})
    thread = thread_fixture(board, %{body: "OP"})
    reply = reply_fixture(board, thread, %{body: "Reply"})

    conn =
      conn
      |> put_req_cookie("browser_token", "token-1234567890123456")
      |> post("/watcher/#{board.uri}/#{reply.id}", %{"_csrf_token" => CSRFProtection.get_csrf_token()})

    assert response(conn, 404)
  end

  test "marks watched thread as seen", %{conn: conn} do
    board = board_fixture(%{uri: "watchseen", title: "Watch Seen"})
    thread = thread_fixture(board, %{body: "Watch me"})
    token = "token-abcdef1234567890"
    thread_id = thread.id

    {:ok, _watch} =
      ThreadWatcher.watch_thread(token, board.uri, thread_id, %{last_seen_post_id: thread_id})

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_header("x-csrf-token", CSRFProtection.get_csrf_token())
      |> patch("/watcher/#{board.uri}/#{thread_id}", %{"last_seen_post_id" => Integer.to_string(thread_id + 5)})

    assert %{"ok" => true, "thread_id" => ^thread_id, "last_seen_post_id" => last_seen_post_id} =
             json_response(conn, 200)

    assert last_seen_post_id == thread_id + 5
  end
end
