defmodule EirinchanWeb.LegacyModControllerTest do
  use EirinchanWeb.ConnCase, async: false
  import Ecto.Query, only: [from: 2]

  alias Eirinchan.IpCrypt
  alias Eirinchan.Posts
  alias Eirinchan.Posts.PublicIds
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

  test "legacy bans route redirects to the browser ban list", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    conn =
      conn
      |> login_moderator(moderator)
      |> get("/mod.php?/bans")

    assert redirected_to(conn) == "/manage/bans/browser"
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

      assert redirected_to(conn) == "/manage/ip/#{cloaked}/browser"
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

    Repo.update_all(from(p in Eirinchan.Posts.Post, where: p.id == ^thread.id),
      set: [ip_subnet: nil]
    )

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

  test "legacy ban24 route creates a global /24 ban", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    thread = thread_fixture(board)

    Repo.update_all(from(p in Eirinchan.Posts.Post, where: p.id == ^thread.id),
      set: [ip_subnet: "198.51.100.161"]
    )

    conn = login_moderator(conn, moderator)

    conn =
      get(
        conn,
        "/mod.php?/#{board.uri}/ban24/#{thread.id}/#{signed_token(conn, "#{board.uri}/ban24/#{thread.id}")}"
      )

    assert redirected_to(conn) == "/#{board.uri}"

    [ban] = Eirinchan.Bans.list_bans()
    assert ban.board_id == nil
    assert ban.ip_subnet == "198.51.100.0/24"
    event = Repo.one!(Eirinchan.Moderation.PostEvent)
    assert event.ip_subnet == "198.51.100.161"
    assert event.banned_subnet == ban.ip_subnet
    assert event.ban_id == ban.id
    assert event.mod_user_id == moderator.id
    assert event.file_count == 0
    assert event.files == []
  end

  test "legacy B24 logs all selected attachments and preserves reply media", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()

    thread =
      thread_fixture(board, %{
        files: [upload_fixture("first.png", "first"), upload_fixture("second.gif", "second")]
      })

    reply = reply_fixture(board, thread, %{file: upload_fixture("reply.png", "reply")})

    Repo.update_all(from(p in Eirinchan.Posts.Post, where: p.id == ^thread.id),
      set: [ip_subnet: "192.0.2.25"]
    )

    conn = login_moderator(conn, moderator)
    path = "#{board.uri}/ban24/#{thread.public_id}"
    response = get(conn, "/mod.php?/#{path}/#{signed_token(conn, path)}")
    assert redirected_to(response) == "/#{board.uri}"

    event = Repo.one!(Eirinchan.Moderation.PostEvent)
    assert event.file_count == 2

    assert Enum.map(event.files, &{&1.position, &1.file_name, &1.file_md5, &1.file_size}) ==
             [{0, thread.file_name, thread.file_md5, thread.file_size}] ++
               Enum.map(
                 thread.extra_files,
                 &{&1.position, &1.file_name, &1.file_md5, &1.file_size}
               )

    assert {:ok, updated} = Posts.get_post(board, thread.public_id)
    assert updated.body == thread.body
    assert updated.file_path == "deleted"
    assert Enum.all?(updated.extra_files, &(&1.file_path == "deleted"))
    refute File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))

    for file <- thread.extra_files,
        do: refute(File.exists?(Eirinchan.Uploads.filesystem_path(file.file_path)))

    assert File.exists?(Eirinchan.Uploads.filesystem_path(reply.file_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(reply.thumb_path))
  end

  test "B24 rejects missing IPs, invalid tokens and non-admin callers without evidence", %{
    conn: conn
  } do
    board = board_fixture()
    thread = thread_fixture(board, %{file: upload_fixture("intact.png", "intact")})

    Repo.update_all(from(p in Eirinchan.Posts.Post, where: p.id == ^thread.id),
      set: [ip_subnet: nil]
    )

    admin_conn = login_moderator(conn, moderator_fixture(%{role: "admin"}))
    path = "#{board.uri}/ban24/#{thread.public_id}"

    assert response(
             get(admin_conn, "/mod.php?/#{path}/#{signed_token(admin_conn, path)}"),
             400
           ) =~ "Post has no IP"

    assert response(get(admin_conn, "/mod.php?/#{path}/invalid-token"), 403)

    janitor = moderator_fixture(%{role: "janitor"}) |> grant_board_access_fixture(board)
    janitor_conn = login_moderator(recycle(conn), janitor)

    assert response(
             get(janitor_conn, "/mod.php?/#{path}/#{signed_token(janitor_conn, path)}"),
             403
           )

    assert Repo.aggregate(Eirinchan.Moderation.PostEvent, :count) == 0
    assert Eirinchan.Bans.list_bans() == []
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
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

    assert redirected_to(conn) == "/#{board.uri}/res/#{PublicIds.public_id(thread)}.html"

    assert {:ok, updated_thread} = Posts.get_post(board, thread.id)
    assert updated_thread.file_path
    assert [%{file_path: "deleted"}] = updated_thread.extra_files
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

    assert redirected_to(conn) == "/#{board.uri}/res/#{PublicIds.public_id(thread)}.html"
    assert {:ok, updated_thread} = Posts.get_post(board, thread.id)
    refute updated_thread.spoiler
    assert [%{spoiler: true}] = updated_thread.extra_files
  end

  test "legacy delete route returns no content for xhr callers", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    thread = thread_fixture(board)

    conn = login_moderator(conn, moderator)
    token = signed_token(conn, "#{board.uri}/delete/#{thread.id}")

    conn =
      conn
      |> put_req_header("x-requested-with", "XMLHttpRequest")
      |> get("/mod.php?/#{board.uri}/delete/#{thread.id}/#{token}")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "cache-control") == ["no-store"]
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
        "report_post_id" => Integer.to_string(PublicIds.public_id(thread)),
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
        "report_post_id" => Integer.to_string(PublicIds.public_id(thread)),
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
end
