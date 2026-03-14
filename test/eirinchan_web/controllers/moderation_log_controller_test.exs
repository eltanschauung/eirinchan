defmodule EirinchanWeb.ModerationLogControllerTest do
  use EirinchanWeb.ConnCase, async: true

  alias Eirinchan.ModerationLog

  test "admin can view the moderation log and non-admin cannot", %{conn: conn} do
    admin = moderator_fixture(%{role: "admin", username: "adminlog"})
    mod = moderator_fixture(%{role: "mod", username: "modlog"})

    {:ok, _entry} =
      ModerationLog.log_action(%{
        mod_user_id: admin.id,
        actor_ip: "198.51.100.12",
        board_uri: "bant",
        text: "Deleted post No. 42"
      })

    admin_page =
      conn
      |> login_moderator(admin)
      |> get("/manage/log/browser")
      |> html_response(200)

    assert admin_page =~ "Moderation log"
    assert admin_page =~ "Deleted post No. 42"
    assert admin_page =~ "adminlog"
    assert admin_page =~ "/manage/ip/"

    mod_conn =
      conn
      |> recycle()
      |> login_moderator(mod)
      |> get("/manage/log/browser")

    assert response(mod_conn, 403) =~ "Manage"
    refute response(mod_conn, 403) =~ "Moderation log"
  end

  test "moderation actions write entries to the log", %{conn: conn} do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "mod", username: "actionmod"}) |> grant_board_access_fixture(board)
    thread = thread_fixture(board)

    conn
    |> login_moderator(moderator)
    |> put_secure_manage_token()
    |> put_req_header("accept", "application/json")
    |> delete("/manage/boards/#{board.uri}/posts/#{thread.id}")
    |> json_response(200)

    [entry | _] = ModerationLog.list_entries(username: "actionmod")
    assert entry.board_uri == board.uri
    assert entry.text =~ "Deleted post No. #{thread.id}"
  end
end
