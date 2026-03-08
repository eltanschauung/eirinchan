defmodule EirinchanWeb.LegacyModControllerTest do
  use EirinchanWeb.ConnCase, async: true

  alias Eirinchan.Posts

  test "legacy IP route redirects moderators to the IP history page", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    conn =
      conn
      |> login_moderator(moderator)
      |> get("/mod.php?/IP/198.51.100.7")

    assert redirected_to(conn) == "/manage/ip/198.51.100.7/browser"
  end

  test "legacy sticky route updates thread state for admins", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    thread = thread_fixture(board)

    conn = login_moderator(conn, moderator)

    conn =
      get(conn, "/mod.php?/#{board.uri}/sticky/#{thread.id}/#{signed_token(conn, "#{board.uri}/sticky/#{thread.id}")}")

    assert redirected_to(conn) == "/#{board.uri}"
    assert {:ok, updated} = Posts.get_post(board, thread.id)
    assert updated.sticky
  end

  test "legacy delete route removes posts for admins", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    thread = thread_fixture(board)

    conn = login_moderator(conn, moderator)

    conn =
      get(conn, "/mod.php?/#{board.uri}/delete/#{thread.id}/#{signed_token(conn, "#{board.uri}/delete/#{thread.id}")}")

    assert redirected_to(conn) == "/#{board.uri}"
    assert {:error, :not_found} = Posts.get_post(board, thread.id)
  end

  defp signed_token(conn, path) do
    EirinchanWeb.ManageSecurity.sign_action(
      Plug.Conn.get_session(conn, :secure_manage_token),
      path
    )
  end
end
