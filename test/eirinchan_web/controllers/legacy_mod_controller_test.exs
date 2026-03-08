defmodule EirinchanWeb.LegacyModControllerTest do
  use EirinchanWeb.ConnCase, async: true

  alias Eirinchan.Posts
  alias Eirinchan.Reports

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

  test "legacy report dismiss route dismisses reports", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    thread = thread_fixture(board)

    report_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "report_post_id" => Integer.to_string(thread.id),
        "reason" => "spam",
        "json_response" => "1"
      })

    assert %{"report_id" => report_id} = json_response(report_conn, 200)

    conn = login_moderator(conn, moderator)

    conn =
      get(
        conn,
        "/mod.php?/reports/#{report_id}/dismiss/#{signed_token(conn, "reports/#{report_id}/dismiss")}"
      )

    assert redirected_to(conn) == "/manage/reports/browser"
    assert Reports.get_report(report_id).dismissed_at
  end

  defp signed_token(conn, path) do
    EirinchanWeb.ManageSecurity.sign_action(
      Plug.Conn.get_session(conn, :secure_manage_token),
      path
    )
  end
end
