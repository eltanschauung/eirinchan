defmodule EirinchanWeb.PublicPostEditControllerTest do
  use EirinchanWeb.ConnCase, async: true

  alias Eirinchan.Posts
  alias Eirinchan.Posts.PublicIds

  test "GET /:board/edit/:post_id renders the public edit form", %{conn: conn} do
    board = board_fixture()
    reply = reply_fixture(board, thread_fixture(board), %{password: "editpw", body: "editable body"})

    page =
      conn
      |> get("/#{board.uri}/edit/#{PublicIds.public_id(reply)}")
      |> html_response(200)

    assert page =~ "Edit post"
    assert page =~ "editable body"
    assert page =~ ~s(name="password")
    assert page =~ ~s(action="/#{board.uri}/edit/#{PublicIds.public_id(reply)}")
  end

  test "public edit page renders the shared global message html", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread, %{password: "editpw", body: "editable body"})

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        global_message: "Visitors: {stats.users_10minutes}\\nPPH: {stats.posts_perhour}"
      })

    page =
      conn
      |> get("/#{board.uri}/edit/#{PublicIds.public_id(reply)}")
      |> html_response(200)

    assert page =~ "Visitors:"
    assert page =~ "PPH:"
    assert page =~ "<br />"
    refute page =~ "{stats.users_10minutes}"
    refute page =~ "{stats.posts_perhour}"
  end

  test "public edit updates a post when the password matches", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread, %{password: "editpw", body: "editable body"})

    conn =
      conn
      |> patch("/#{board.uri}/edit/#{PublicIds.public_id(reply)}", %{
        "name" => "editor",
        "subject" => "updated",
        "body" => "updated body",
        "password" => "editpw"
      })

    assert redirected_to(conn) ==
             "/#{board.uri}/res/#{PublicIds.public_id(thread)}.html#p#{PublicIds.public_id(reply)}"

    {:ok, updated_reply} = Posts.get_post(board, PublicIds.public_id(reply))
    assert updated_reply.name == "editor"
    assert updated_reply.subject == "updated"
    assert updated_reply.body == "updated body"
  end

  test "public edit rejects an incorrect password", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread, %{password: "editpw", body: "editable body"})

    page =
      conn
      |> patch("/#{board.uri}/edit/#{PublicIds.public_id(reply)}", %{
        "body" => "hijacked body",
        "password" => "wrongpw"
      })
      |> html_response(422)

    assert page =~ "Incorrect password."

    {:ok, unchanged_reply} = Posts.get_post(board, PublicIds.public_id(reply))
    assert unchanged_reply.body == "editable body"
  end

  test "admin can edit through the public edit route without the post password", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread, %{password: "editpw", body: "editable body"})
    admin = moderator_fixture(%{role: "admin"})
    grant_board_access_fixture(admin, board)

    conn =
      conn
      |> login_moderator(admin)
      |> patch("/#{board.uri}/edit/#{PublicIds.public_id(reply)}", %{
        "body" => "admin body",
        "password" => ""
      })

    assert redirected_to(conn) ==
             "/#{board.uri}/res/#{PublicIds.public_id(thread)}.html#p#{PublicIds.public_id(reply)}"

    {:ok, updated_reply} = Posts.get_post(board, PublicIds.public_id(reply))
    assert updated_reply.body == "admin body"
  end

  test "non-admin moderators do not bypass the public edit password check", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread, %{password: "editpw", body: "editable body"})
    mod = moderator_fixture(%{role: "mod"})
    grant_board_access_fixture(mod, board)

    page =
      conn
      |> login_moderator(mod)
      |> patch("/#{board.uri}/edit/#{PublicIds.public_id(reply)}", %{
        "body" => "mod body",
        "password" => ""
      })
      |> html_response(422)

    assert page =~ "Incorrect password."

    {:ok, unchanged_reply} = Posts.get_post(board, PublicIds.public_id(reply))
    assert unchanged_reply.body == "editable body"
  end
end
