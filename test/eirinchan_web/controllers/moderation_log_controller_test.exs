defmodule EirinchanWeb.ModerationLogControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.IpCrypt
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

  test "moderation log cloaks actor_ip by default", %{conn: conn} do
    with_instance_config(%{"ipcrypt_key" => "whalenic"}, fn ->
      admin = moderator_fixture(%{role: "admin", username: "adminlogcloak"})

      {:ok, _entry} =
        ModerationLog.log_action(%{
          mod_user_id: admin.id,
          actor_ip: "198.51.100.12",
          board_uri: "bant",
          text: "Deleted post No. 99"
        })

      page =
        conn
        |> Map.put(:remote_ip, {203, 0, 113, 44})
        |> login_moderator(admin)
        |> get("/manage/log/browser")
        |> html_response(200)

      cloaked = IpCrypt.cloak_ip("198.51.100.12")

      assert page =~ cloaked
      encoded_cloak = URI.encode(cloaked, &URI.char_unreserved?/1)
      assert page =~ "/manage/ip/#{encoded_cloak}/browser"
      refute page =~ "198.51.100.12"
    end)
  end

  test "moderation log shows raw actor_ip for immune viewers", %{conn: conn} do
    with_instance_config(
      %{"ipcrypt_key" => "whalenic", "ipcrypt_immune_ip" => "198.51.100.0/24"},
      fn ->
        admin = moderator_fixture(%{role: "admin", username: "adminlogimmune"})

        {:ok, _entry} =
          ModerationLog.log_action(%{
            mod_user_id: admin.id,
            actor_ip: "203.0.113.12",
            board_uri: "bant",
            text: "Deleted post No. 100"
          })

        page =
          conn
          |> Map.put(:remote_ip, {198, 51, 100, 44})
          |> login_moderator(admin)
          |> get("/manage/log/browser")
          |> html_response(200)

        assert page =~ "203.0.113.12"
        assert page =~ "/manage/ip/203.0.113.12/browser"
      end
    )
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
