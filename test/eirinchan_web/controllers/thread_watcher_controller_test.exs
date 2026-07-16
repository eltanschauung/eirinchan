defmodule EirinchanWeb.ThreadWatcherControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.Posts.PublicIds

  alias Eirinchan.ThreadWatcher
  test "watches and unwatches a thread with browser token", %{conn: conn} do
    board = board_fixture(%{uri: "watch", title: "Watch"})
    thread = thread_fixture(board, %{body: "Watch me"})
    token = browser_token("watch-index")
    thread_id = PublicIds.public_id(thread)

    {conn, csrf_token} = json_conn_with_csrf(conn, token)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-csrf-token", csrf_token)
      |> post("/watcher/#{board.uri}/#{PublicIds.public_id(thread)}")

    assert %{
             "ok" => true,
             "watched" => true,
             "thread_id" => ^thread_id,
             "watcher_count" => 1,
             "watcher_unread_count" => 0,
             "watcher_you_count" => 0
           } = json_response(conn, 200)

    assert ThreadWatcher.watched?(token, board.uri, thread.id)

    {conn, csrf_token} = json_conn_with_csrf(build_conn(), token)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_header("x-csrf-token", csrf_token)
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

  test "rejects JSON watcher mutations without a CSRF token", %{conn: conn} do
    board = board_fixture(%{uri: "watchcsrf", title: "Watch CSRF"})
    thread = thread_fixture(board, %{body: "Watch me"})

    conn =
      conn
      |> put_req_cookie("browser_token", browser_token("watch-csrf"))
      |> put_req_header("accept", "application/json")
      |> post("/watcher/#{board.uri}/#{PublicIds.public_id(thread)}")

    assert %{"csrf" => true} = json_response(conn, 403)
  end

  test "returns not found for reply ids", %{conn: conn} do
    board = board_fixture(%{uri: "watch404", title: "Watch 404"})
    thread = thread_fixture(board, %{body: "OP"})
    reply = reply_fixture(board, thread, %{body: "Reply"})
    token = browser_token("watch-invalid-thread")

    {conn, csrf_token} = json_conn_with_csrf(conn, token)

    conn =
      conn
      |> put_req_header("x-csrf-token", csrf_token)
      |> post("/watcher/#{board.uri}/#{PublicIds.public_id(reply)}")

    assert response(conn, 404)
  end

  test "marks watched thread as seen", %{conn: conn} do
    board = board_fixture(%{uri: "watchseen", title: "Watch Seen"})
    thread = thread_fixture(board, %{body: "Watch me"})
    token = browser_token("watch-moved")
    thread_id = PublicIds.public_id(thread)

    {:ok, _watch} =
      ThreadWatcher.watch_thread(token, board.uri, thread.id, %{last_seen_post_id: thread.id})

    {conn, csrf_token} = json_conn_with_csrf(conn, token)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_header("x-csrf-token", csrf_token)
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

  test "rejects a last-seen post from a different thread", %{conn: conn} do
    board = board_fixture(%{uri: "watchscope", title: "Watch Scope"})
    watched_thread = thread_fixture(board, %{body: "Watched"})
    other_thread = thread_fixture(board, %{body: "Other"})
    other_reply = reply_fixture(board, other_thread, %{body: "Not part of the watched thread"})
    token = browser_token("watch-seen-scope")

    assert {:ok, _watch} =
             ThreadWatcher.watch_thread(token, board.uri, watched_thread.id, %{
               last_seen_post_id: watched_thread.id
             })

    {conn, csrf_token} = json_conn_with_csrf(conn, token)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_header("x-csrf-token", csrf_token)
      |> patch("/watcher/#{board.uri}/#{PublicIds.public_id(watched_thread)}", %{
        "last_seen_post_id" => Integer.to_string(PublicIds.public_id(other_reply))
      })

    assert response(conn, 422) == ""

    [watch] = ThreadWatcher.list_watches(token)
    assert watch.last_seen_post_id == watched_thread.id
  end

  test "unwatching a missing thread is idempotent", %{conn: conn} do
    board = board_fixture(%{uri: "watchstale", title: "Watch Stale"})
    token = browser_token("watch-stale-delete")
    {conn, csrf_token} = json_conn_with_csrf(conn, token)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_header("x-csrf-token", csrf_token)
      |> delete("/watcher/#{board.uri}/123456")

    assert %{
             "ok" => true,
             "watched" => false,
             "thread_id" => 123_456,
             "watcher_count" => 0
           } = json_response(conn, 200)
  end

  test "clears all watched threads for the browser token", %{conn: conn} do
    board = board_fixture(%{uri: "watchclear", title: "Watch Clear"})
    token = browser_token("watch-clear")
    thread = thread_fixture(board, %{body: "OP"})

    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, board.uri, thread.id)
    {conn, csrf_token} = json_conn_with_csrf(conn, token)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_header("x-csrf-token", csrf_token)
      |> delete("/watcher")

    assert %{
             "ok" => true,
             "watcher_count" => 0,
             "watcher_unread_count" => 0,
             "watcher_you_count" => 0
           } = json_response(conn, 200)

    assert ThreadWatcher.list_watches(token) == []
  end

  defp json_conn_with_csrf(conn, browser_token) do
    csrf_conn =
      conn
      |> put_req_cookie("__Host-eirinchan_browser", Eirinchan.BrowserIdentity.issue(browser_token))
      |> get("/csrf-token")
    %{"csrf_token" => csrf_token} = json_response(csrf_conn, 200)

    {recycle(csrf_conn) |> put_req_header("accept", "application/json"), csrf_token}
  end
end
