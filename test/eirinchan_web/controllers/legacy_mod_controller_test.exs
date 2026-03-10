defmodule EirinchanWeb.LegacyModControllerTest do
  use EirinchanWeb.ConnCase, async: true
  import Ecto.Query, only: [from: 2]

  alias Eirinchan.IpCrypt
  alias Eirinchan.Posts
  alias Eirinchan.Repo
  alias Eirinchan.Reports

  test "legacy IP route redirects moderators to the IP history page", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    conn =
      conn
      |> login_moderator(moderator)
      |> get("/mod.php?/IP/198.51.100.7")

    assert redirected_to(conn) == "/manage/ip/198.51.100.7/browser"
  end

  test "legacy IP route accepts cloaked ips", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    with_instance_config(%{"ipcrypt_key" => "whalenic"}, fn ->
      IpCrypt.configure_for_request(%{ipcrypt_key: "whalenic"}, "203.0.113.5")
      cloaked = IpCrypt.cloak_ip("198.51.100.7")

      conn =
        conn
        |> login_moderator(moderator)
        |> get("/mod.php?/IP/#{cloaked}")

      assert redirected_to(conn) == "/manage/ip/198.51.100.7/browser"
    end)
  end

  test "legacy sticky route updates thread state for admins", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    thread = thread_fixture(board)

    conn = login_moderator(conn, moderator)

    conn =
      get(
        conn,
        "/mod.php?/#{board.uri}/sticky/#{thread.id}/#{signed_token(conn, "#{board.uri}/sticky/#{thread.id}")}"
      )

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
      get(
        conn,
        "/mod.php?/#{board.uri}/delete/#{thread.id}/#{signed_token(conn, "#{board.uri}/delete/#{thread.id}")}"
      )

    assert redirected_to(conn) == "/#{board.uri}"
    assert {:error, :not_found} = Posts.get_post(board, thread.id)
  end

  test "legacy deletebyip route does not crash when a post has no stored ip", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    thread = thread_fixture(board)

    Repo.update_all(from(p in Eirinchan.Posts.Post, where: p.id == ^thread.id), set: [ip_subnet: nil])

    conn = login_moderator(conn, moderator)

    conn =
      get(
        conn,
        "/mod.php?/#{board.uri}/deletebyip/#{thread.id}/#{signed_token(conn, "#{board.uri}/deletebyip/#{thread.id}")}"
      )

    assert redirected_to(conn) == "/#{board.uri}"
    assert {:ok, still_present} = Posts.get_post(board, thread.id)
    assert still_present.id == thread.id
  end

  test "legacy deletefile route removes a single file for janitors", %{conn: conn} do
    board = board_fixture()

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
    assert {:ok, thread} = Posts.get_post(board, thread_id)

    moderator = moderator_fixture(%{role: "janitor"}) |> grant_board_access_fixture(board)
    conn = login_moderator(conn, moderator)

    conn =
      get(
        conn,
        "/mod.php?/#{board.uri}/deletefile/#{thread.id}/1/#{signed_token(conn, "#{board.uri}/deletefile/#{thread.id}/1")}"
      )

    assert redirected_to(conn) =~ "/#{board.uri}/res/#{thread.id}"

    assert {:ok, updated_thread} = Posts.get_post(board, thread.id)
    assert updated_thread.file_path
    assert updated_thread.extra_files == []
  end

  test "legacy spoiler route spoilerizes a single file for janitors", %{conn: conn} do
    board = board_fixture()

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
    assert {:ok, thread} = Posts.get_post(board, thread_id)

    moderator = moderator_fixture(%{role: "janitor"}) |> grant_board_access_fixture(board)
    conn = login_moderator(conn, moderator)

    conn =
      get(
        conn,
        "/mod.php?/#{board.uri}/spoiler/#{thread.id}/1/#{signed_token(conn, "#{board.uri}/spoiler/#{thread.id}/1")}"
      )

    assert redirected_to(conn) =~ "/#{board.uri}/res/#{thread.id}"
    assert {:ok, updated_thread} = Posts.get_post(board, thread.id)
    refute updated_thread.spoiler
    assert [%{spoiler: true}] = updated_thread.extra_files
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

  test "legacy report dismiss&all route dismisses reports by reporter ip", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    thread = thread_fixture(board)

    report_conn =
      conn
      |> Map.put(:remote_ip, {198, 51, 100, 9})
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
        "/mod.php?/reports/#{report_id}/dismiss&all/#{signed_token(conn, "reports/#{report_id}/dismiss&all")}"
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

  defp with_instance_config(config, fun) do
    original_path = Application.get_env(:eirinchan, :instance_config_path)
    path = Path.join(System.tmp_dir!(), "eirinchan-ipcrypt-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(config))

    try do
      Application.put_env(:eirinchan, :instance_config_path, path)
      fun.()
    after
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end
  end
end
