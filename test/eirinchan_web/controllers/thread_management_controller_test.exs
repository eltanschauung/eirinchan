defmodule EirinchanWeb.ThreadManagementControllerTest do
  use EirinchanWeb.ConnCase, async: true

  alias Eirinchan.Posts.PublicIds

  test "shows and updates board-scoped thread state", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{threads_per_page: 1}})
    older_thread = thread_fixture(board, %{body: "Older body", subject: "Older"})
    _newer_thread = thread_fixture(board, %{body: "Newer body", subject: "Newer"})
    older_thread_id = PublicIds.public_id(older_thread)
    moderator = moderator_fixture()

    conn =
      conn
      |> login_moderator(moderator)
      |> put_req_header("accept", "application/json")

    assert %{"data" => %{"id" => ^older_thread_id, "sticky" => false, "locked" => false}} =
             conn
             |> get("/manage/boards/#{board.uri}/threads/#{older_thread_id}")
             |> json_response(200)

    assert %{
             "data" => %{
               "id" => ^older_thread_id,
               "sticky" => true,
               "locked" => true,
               "cycle" => true,
               "sage" => true
             }
           } =
             conn
             |> recycle()
             |> login_moderator(moderator)
             |> put_secure_manage_token()
             |> patch("/manage/boards/#{board.uri}/threads/#{older_thread_id}", %{
               "sticky" => "true",
               "locked" => "true",
               "cycle" => "true",
               "sage" => "true"
             })
             |> json_response(200)

    first_page =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_req_header("accept", "text/html")
      |> get("/#{board.uri}")
      |> html_response(200)

    assert first_page =~ "Older"
    assert first_page =~ "[Sticky]"
    assert first_page =~ "[Locked]"
    assert first_page =~ "[Cyclical]"
    assert first_page =~ "[Bumplocked]"
  end

  test "locked thread state blocks posting replies after management update", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    moderator = moderator_fixture()

    conn =
      conn
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{board.uri}/threads/#{PublicIds.public_id(thread)}", %{"locked" => "true"})

    assert %{"data" => %{"locked" => true}} = json_response(conn, 200)

    locked_reply =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "text/html")
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "thread" => Integer.to_string(PublicIds.public_id(thread)),
        "body" => "reply body",
        "json_response" => "1",
        "post" => "New Reply"
      })

    assert %{"error" => "Thread locked. You may not reply at this time."} =
             json_response(locked_reply, 403)
  end

  test "moves threads between boards when moderator has access to both", %{conn: conn} do
    source_board = board_fixture()
    target_board = board_fixture()
    thread = thread_fixture(source_board, %{body: "Move me"})
    _reply = reply_fixture(source_board, thread, %{body: "Reply follows"})

    moderator =
      moderator_fixture(%{role: "mod"})
      |> grant_board_access_fixture(source_board)
      |> grant_board_access_fixture(target_board)

    conn =
      conn
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{source_board.uri}/threads/#{PublicIds.public_id(thread)}/move", %{
        "target_board_uri" => target_board.uri
      })

    assert %{"data" => %{"id" => thread_id, "board_id" => target_board_id}} =
             json_response(conn, 200)

    assert thread_id == 1
    assert target_board_id == target_board.id

    assert %{"error" => "not_found"} =
             Phoenix.ConnTest.build_conn()
             |> login_moderator(moderator)
             |> put_req_header("accept", "application/json")
             |> get("/manage/boards/#{source_board.uri}/threads/#{PublicIds.public_id(thread)}")
             |> json_response(404)

    assert %{"data" => %{"id" => ^thread_id, "board_id" => ^target_board_id}} =
             Phoenix.ConnTest.build_conn()
             |> login_moderator(moderator)
             |> put_req_header("accept", "application/json")
             |> get("/manage/boards/#{target_board.uri}/threads/#{thread_id}")
             |> json_response(200)
  end
end
