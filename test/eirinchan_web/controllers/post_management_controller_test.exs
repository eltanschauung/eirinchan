defmodule EirinchanWeb.PostManagementControllerTest do
  use EirinchanWeb.ConnCase, async: true

  alias Eirinchan.Posts.PublicIds

  test "shows, edits, deletes files, spoilerizes, and deletes board posts", %{conn: conn} do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(board)

    create_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "body" => "Opening body",
        "files" => [
          upload_fixture("first.png", "first"),
          upload_fixture("second.gif", "second")
        ],
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => thread_id} = json_response(create_conn, 200)

    show_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_req_header("accept", "application/json")
      |> get("/manage/boards/#{board.uri}/posts/#{thread_id}")

    assert %{
             "data" => %{
               "id" => ^thread_id,
               "body" => "Opening body",
               "file_path" => file_path,
               "extra_files" => [_extra]
             }
           } = json_response(show_conn, 200)

    assert is_binary(file_path)

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{board.uri}/posts/#{thread_id}", %{
        "body" => "<strong>Updated</strong>"
      })

    assert %{
             "data" => %{
               "id" => ^thread_id,
               "body" => "<strong>Updated</strong>"
             }
           } = json_response(update_conn, 200)

    spoiler_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{board.uri}/posts/#{thread_id}/spoiler", %{})

    assert %{
             "data" => %{
               "id" => ^thread_id,
               "spoiler" => true,
               "extra_files" => [%{"spoiler" => true}]
             }
           } = json_response(spoiler_conn, 200)

    create_conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "body" => "Opening body two",
        "files" => [
          upload_fixture("third.png", "third"),
          upload_fixture("fourth.gif", "fourth")
        ],
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => second_thread_id} = json_response(create_conn, 200)

    single_spoiler_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{board.uri}/posts/#{second_thread_id}/spoiler", %{
        "file_index" => "1"
      })

    assert %{
             "data" => %{
               "id" => ^second_thread_id,
               "spoiler" => false,
               "extra_files" => [%{"spoiler" => true}]
             }
           } = json_response(single_spoiler_conn, 200)

    delete_single_file_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> delete("/manage/boards/#{board.uri}/posts/#{thread_id}/file", %{"file_index" => "1"})

    assert %{
             "data" => %{
               "id" => ^thread_id,
               "file_path" => primary_file_path,
               "extra_files" => [%{"file_path" => "deleted"}]
             }
           } = json_response(delete_single_file_conn, 200)

    assert is_binary(primary_file_path)

    delete_file_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> delete("/manage/boards/#{board.uri}/posts/#{thread_id}/file")

    assert %{
             "data" => %{
               "id" => ^thread_id,
               "file_path" => "deleted",
               "extra_files" => [%{"file_path" => "deleted"}]
             }
           } = json_response(delete_file_conn, 200)

    delete_post_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> delete("/manage/boards/#{board.uri}/posts/#{thread_id}")

    assert %{"data" => %{"deleted_post_id" => ^thread_id, "thread_deleted" => true}} =
             json_response(delete_post_conn, 200)
  end

  test "post management routes reject moderators without access", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    moderator = moderator_fixture(%{role: "mod"})

    conn =
      conn
      |> login_moderator(moderator)
      |> put_req_header("accept", "application/json")
      |> get("/manage/boards/#{board.uri}/posts/#{thread.id}")

    assert %{"error" => "forbidden"} = json_response(conn, 403)
  end

  test "moves replies between boards and threads", %{conn: conn} do
    source_board = board_fixture()
    target_board = board_fixture()
    source_thread = thread_fixture(source_board)
    target_thread = thread_fixture(target_board)
    reply = reply_fixture(source_board, source_thread, %{body: "Move reply body"})

    moderator =
      moderator_fixture(%{role: "mod"})
      |> grant_board_access_fixture(source_board)
      |> grant_board_access_fixture(target_board)

    conn =
      conn
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{source_board.uri}/posts/#{reply.id}/move", %{
        "target_board_uri" => target_board.uri,
        "target_thread_id" => Integer.to_string(PublicIds.public_id(target_thread))
      })

    assert %{
             "data" => %{
               "id" => reply_id,
               "board_id" => target_board_id,
               "thread_id" => target_thread_id,
               "body" => "Move reply body"
             }
           } = json_response(conn, 200)

    {:ok, moved_reply} = Eirinchan.Posts.get_post_by_internal_id(target_board, reply.id)

    assert reply_id == PublicIds.public_id(moved_reply)
    assert target_board_id == target_board.id
    assert target_thread_id == PublicIds.public_id(target_thread)
  end
end
