defmodule EirinchanWeb.ManagePageControllerTest do
  use EirinchanWeb.ConnCase, async: true

  alias Eirinchan.Feedback

  test "login page renders and browser login redirects to the dashboard", %{conn: conn} do
    moderator = moderator_fixture(%{username: "admin", password: "secret123"})
    _board = board_fixture(%{uri: "bant", title: "International Random"})

    login_page = conn |> get("/manage/login") |> html_response(200)
    refute login_page =~ "Moderator Login"
    assert login_page =~ ~s(name="username")
    assert login_page =~ ~s(name="password")
    assert login_page =~ ~s(value="Continue")
    assert login_page =~ ~s(class="boardlist")
    assert login_page =~ ~s(src="/main.js)
    assert login_page =~ ~s(src="/js/jquery.min.js)
    assert login_page =~ ~s(src="/js/options.js)

    conn =
      conn
      |> recycle()
      |> post("/manage/login/browser", %{
        "username" => moderator.username,
        "password" => "secret123"
      })

    assert redirected_to(conn) == "/manage"

    dashboard =
      conn
      |> recycle()
      |> get("/manage")
      |> html_response(200)

    assert dashboard =~ "Signed in as"
    assert dashboard =~ moderator.username
    assert dashboard =~ "Report queue (0)"
    assert dashboard =~ "Feedback (0)"
    assert dashboard =~ "Ban appeals (0)"
    assert dashboard =~ ~s(class="boardlist")
  end

  test "feedback browser page renders the moderation queue", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    conn =
      conn
      |> post("/feedback", %{"body" => "Needs review", "json_response" => "1"})

    assert %{"feedback_id" => feedback_id} = json_response(conn, 200)
    assert Feedback.get_feedback(feedback_id)

    page =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/feedback/browser")
      |> html_response(200)

    assert page =~ "Feedback"
    assert page =~ "Needs review"
    assert page =~ "Mark as Read"
    assert page =~ "Add Note"
    assert page =~ "Delete"
  end

  test "report queue renders reporter ip and dismiss+ link", %{conn: conn} do
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

    page =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/reports/browser")
      |> html_response(200)

    assert page =~ "Reported by:"
    assert page =~ "/mod.php?/IP/198.51.100.9"
    assert page =~ "/mod.php?/reports/#{report_id}/dismiss&amp;all/"
    assert page =~ "Dismiss+"
  end

  test "browser dashboard redirects to setup when no admin exists", %{conn: conn} do
    conn = get(conn, "/manage/login")
    assert redirected_to(conn) == "/setup"
  end

  test "admin can update boardlist configuration from the dashboard", %{conn: conn} do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-boardlist-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    moderator = moderator_fixture(%{role: "admin"})
    _board = board_fixture(%{uri: "bant", title: "International Random"})

    dashboard =
      conn
      |> login_moderator(moderator)
      |> get("/manage")
      |> html_response(200)

    assert dashboard =~ "Boardlist Configuration"

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> patch("/manage/boardlist/browser", %{
        "boardlist_json" => """
        [
          ["bant"],
          {"Administration": "/manage/login"},
          {"Home": "/"}
        ]
        """
      })

    assert redirected_to(update_conn) == "/manage/boardlist/browser"

    persisted = File.read!(path)
    assert persisted =~ "\"label\": \"Administration\""
    assert persisted =~ "\"href\": \"/manage/login\""
    assert persisted =~ "\"label\": \"bant\""

    assert Eirinchan.Boardlist.encode_for_edit(Eirinchan.Boards.list_boards()) =~
             "\"Administration\""
  end

  test "admin can update dnsbl configuration from the dashboard", %{conn: conn} do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(System.tmp_dir!(), "eirinchan-dnsbl-#{System.unique_integer([:positive])}.json")

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    moderator = moderator_fixture(%{role: "admin"})

    dashboard =
      conn
      |> login_moderator(moderator)
      |> get("/manage")
      |> html_response(200)

    assert dashboard =~ "DNSBL Configuration"

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> patch("/manage/dnsbl/browser", %{
        "dnsbl_json" => """
        [
          ["rbl.efnetrbl.org", 4],
          {
            "lookup": "%.key.dnsbl.httpbl.org",
            "expectation": {"type": "httpbl", "max_days": 14, "min_threat": 5},
            "display_name": "dnsbl.httpbl.org"
          }
        ]
        """,
        "dnsbl_exceptions" => "203.0.113.9\n198.51.100.0/24"
      })

    assert redirected_to(update_conn) == "/manage/dnsbl/browser"

    persisted = File.read!(path)
    assert persisted =~ "\"dnsbl\""
    assert persisted =~ "\"rbl.efnetrbl.org\""
    assert persisted =~ "\"dnsbl.httpbl.org\""
    assert persisted =~ "\"dnsbl_exceptions\""
    assert persisted =~ "\"203.0.113.9\""
    assert persisted =~ "\"198.51.100.0/24\""
  end

  test "admin can update flags configuration from the dashboard", %{conn: conn} do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(System.tmp_dir!(), "eirinchan-flags-#{System.unique_integer([:positive])}.json")

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    moderator = moderator_fixture(%{role: "admin"})

    dashboard =
      conn
      |> login_moderator(moderator)
      |> get("/manage")
      |> html_response(200)

    assert dashboard =~ "Flag Configuration"

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> patch("/manage/flags/browser", %{
        "country_flags" => "false",
        "allow_no_country" => "false",
        "country_flags_condensed" => "false",
        "country_flags_condensed_css" => "static/flags/flags.css",
        "display_flags" => "true",
        "uri_flags" => "static/flags/%s.png",
        "flag_style" => "width:16px;height:11px;",
        "user_flag" => "true",
        "multiple_flags" => "true",
        "default_user_flag" => "country",
        "user_flags_json" => ~s({"country":"Country","pisces":"Pisces","aquarius":"Aquarius"})
      })

    assert redirected_to(update_conn) == "/manage/flags/browser"

    persisted = File.read!(path)
    assert persisted =~ "\"uri_flags\": \"static/flags/%s.png\""
    assert persisted =~ "\"user_flag\": true"
    assert persisted =~ "\"multiple_flags\": true"
    assert persisted =~ "\"country\": \"Country\""
    assert persisted =~ "\"pisces\": \"Pisces\""
  end

  test "flags editor shows vichan defaults before overrides exist", %{conn: conn} do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-flags-defaults-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    moderator = moderator_fixture(%{role: "admin"})

    page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/flags/browser")
      |> html_response(200)

    assert page =~ "Flags Configuration"
    assert page =~ "static/flags/%s.png"
    assert page =~ "width:16px;height:11px;"
    assert page =~ "Example user_flags:"
  end

  test "dashboard no longer links to a standalone faq editor", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    dashboard =
      conn
      |> login_moderator(moderator)
      |> get("/manage")
      |> html_response(200)

    refute dashboard =~ "FAQ Editor"
    assert dashboard =~ "Manage themes"
  end

  test "dnsbl editor shows vichan defaults before overrides exist", %{conn: conn} do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-dnsbl-defaults-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    moderator = moderator_fixture(%{role: "admin"})

    page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/dnsbl/browser")
      |> html_response(200)

    assert page =~ "rbl.efnetrbl.org"
    assert page =~ "127.0.0.1"
  end

  test "browser dashboard redirects to login when admin exists but session is missing", %{
    conn: conn
  } do
    _moderator = moderator_fixture(%{role: "admin"})

    conn = get(conn, "/manage")

    assert redirected_to(conn) == "/manage/login"
  end

  test "admin browser dashboard creates boards", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    uri = "tea#{System.unique_integer([:positive])}"

    conn =
      conn
      |> login_moderator(moderator)
      |> post("/manage/boards/browser", %{"uri" => uri, "title" => "Tea", "subtitle" => "Board"})

    assert redirected_to(conn) == "/#{uri}"

    board_page =
      conn
      |> recycle()
      |> get("/#{uri}")
      |> html_response(200)

    assert board_page =~ "/#{uri}/ - Tea"
    assert board_page =~ ~s(var active_page = "index", board_name = "#{uri}")
    assert board_page =~ ~s(src="/main.js)
  end

  test "admin browser dashboard updates and deletes boards", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    board =
      board_fixture(%{
        uri: "tea#{System.unique_integer([:positive])}",
        title: "Tea",
        subtitle: "Board"
      })

    update_conn =
      conn
      |> login_moderator(moderator)
      |> patch("/manage/boards/#{board.uri}/browser", %{
        "title" => "Tea Time",
        "subtitle" => "Updated"
      })

    assert redirected_to(update_conn) == "/manage"

    dashboard =
      update_conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage")
      |> html_response(200)

    assert dashboard =~ "Tea Time"
    assert dashboard =~ "Updated"

    delete_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> delete("/manage/boards/#{board.uri}/browser")

    assert redirected_to(delete_conn) == "/manage"
    refute Eirinchan.Boards.get_board_by_uri(board.uri)
  end

  test "browser dashboard can rebuild accessible boards", %{conn: conn} do
    alias Eirinchan.Build
    alias Eirinchan.Posts
    alias Eirinchan.Runtime.Config

    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{config_overrides: %{generation_strategy: "defer"}})
    File.rm_rf!(Path.join(Build.board_root(), board.uri))
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Deferred body",
                 "subject" => "Deferred subject",
                 "post" => "New Topic"
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    refute File.exists?(Path.join([Build.board_root(), board.uri, "res", "#{thread.id}.html"]))

    rebuild_conn =
      conn
      |> login_moderator(moderator)
      |> post("/manage/boards/#{board.uri}/browser/rebuild")

    assert redirected_to(rebuild_conn) == "/manage"
    assert File.exists?(Path.join([Build.board_root(), board.uri, "res", "#{thread.id}.html"]))
  end

  test "browser news management creates, updates, and deletes entries", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    create_conn =
      conn
      |> login_moderator(moderator)
      |> post("/manage/news/browser", %{"title" => "Launch", "body" => "Site is live"})

    assert redirected_to(create_conn) == "/manage/news/browser"

    news_page =
      create_conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/news/browser")
      |> html_response(200)

    assert news_page =~ "Manage News"
    assert news_page =~ "Launch"
    assert news_page =~ "Site is live"

    [entry] = Eirinchan.News.list_entries()

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> patch("/manage/news/browser/#{entry.id}", %{
        "title" => "Launch Updated",
        "body" => "Site is more live"
      })

    assert redirected_to(update_conn) == "/manage/news/browser"

    public_news =
      update_conn
      |> recycle()
      |> get("/news")
      |> html_response(200)

    assert public_news =~ "Launch Updated"
    assert public_news =~ "Site is more live"

    delete_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> delete("/manage/news/browser/#{entry.id}")

    assert redirected_to(delete_conn) == "/manage/news/browser"
    assert Eirinchan.News.list_entries() == []
  end

  test "browser announcement management creates, updates, and deletes the site announcement", %{
    conn: conn
  } do
    moderator = moderator_fixture(%{role: "admin"})

    create_conn =
      conn
      |> login_moderator(moderator)
      |> post("/manage/announcement/browser", %{
        "title" => "Banner",
        "body" => "Important notice"
      })

    assert redirected_to(create_conn) == "/manage/announcement/browser"

    announcement_page =
      create_conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/announcement/browser")
      |> html_response(200)

    assert announcement_page =~ "Manage Announcement"
    assert announcement_page =~ "Banner"
    assert announcement_page =~ "Important notice"

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> post("/manage/announcement/browser", %{
        "title" => "Banner Updated",
        "body" => "Important notice updated"
      })

    assert redirected_to(update_conn) == "/manage/announcement/browser"

    announcement_page =
      update_conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/announcement/browser")
      |> html_response(200)

    assert announcement_page =~ "Banner Updated"
    assert announcement_page =~ "Important notice updated"

    home_page =
      update_conn
      |> recycle()
      |> get("/")
      |> html_response(200)

    assert home_page =~ "Recent Posts"
    assert home_page =~ "Stats"

    delete_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> delete("/manage/announcement/browser")

    assert redirected_to(delete_conn) == "/manage/announcement/browser"
    assert Eirinchan.Announcement.current() == nil
  end

  test "browser custom page management creates, updates, and deletes pages", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    create_conn =
      conn
      |> login_moderator(moderator)
      |> post("/manage/pages/browser", %{
        "slug" => "rules",
        "title" => "Rules",
        "body" => "Be civil"
      })

    assert redirected_to(create_conn) == "/manage/pages/browser"

    pages_page =
      create_conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/pages/browser")
      |> html_response(200)

    assert pages_page =~ "Manage Custom Pages"
    assert pages_page =~ "Rules"
    assert pages_page =~ "Be civil"

    [page] = Eirinchan.CustomPages.list_pages()

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> patch("/manage/pages/browser/#{page.id}", %{
        "slug" => "rules",
        "title" => "Board Rules",
        "body" => "Still be civil"
      })

    assert redirected_to(update_conn) == "/manage/pages/browser"

    public_page =
      update_conn
      |> recycle()
      |> get("/pages/rules")
      |> html_response(200)

    assert public_page =~ "Board Rules"
    assert public_page =~ "Still be civil"

    delete_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> delete("/manage/pages/browser/#{page.id}")

    assert redirected_to(delete_conn) == "/manage/pages/browser"
    assert Eirinchan.CustomPages.list_pages() == []
  end

  test "browser recent posts page filters by board, query, and ip", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})

    other_board =
      board_fixture(%{uri: "meta#{System.unique_integer([:positive])}", title: "Meta"})

    {:ok, matching_post, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{"body" => "green leaf", "subject" => "teaware", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{
          referer: "http://example.test/#{board.uri}/index.html",
          remote_ip: {198, 51, 100, 7}
        }
      )

    {:ok, other_post, _meta} =
      Eirinchan.Posts.create_post(
        other_board,
        %{"body" => "other board", "subject" => "meta", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, other_board.config_overrides),
        request: %{
          referer: "http://example.test/#{other_board.uri}/index.html",
          remote_ip: {203, 0, 113, 9}
        }
      )

    page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/recent-posts/browser", %{
        "board" => board.uri,
        "query" => "leaf",
        "ip" => "198.51.100.7",
        "limit" => "10"
      })
      |> html_response(200)

    assert page =~ "Recent Posts"
    assert page =~ ~s(<script type="text/javascript" src="/js/mod/recent-posts.js")
    assert page =~ ~s(class="post-wrapper")
    assert page =~ ~s(class="eita-link")
    assert page =~ ~s(class="thread")
    assert page =~ ~s(class="post op")
    assert page =~ ~s(class="controls op")
    assert page =~ Integer.to_string(matching_post.id)
    assert page =~ "green leaf"
    refute page =~ ~s(id="op_#{other_post.id}")
  end

  test "browser dashboard exposes global report queue and ban appeals management", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})
    thread = thread_fixture(board, %{body: "Thread body"})

    report_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "report_post_id" => Integer.to_string(thread.id),
        "reason" => "Spam",
        "json_response" => "1"
      })

    assert %{"report_id" => report_id} = json_response(report_conn, 200)

    {:ok, ban} =
      Eirinchan.Bans.create_ban(%{
        board_id: board.id,
        mod_user_id: moderator.id,
        ip_subnet: "198.51.100.9",
        reason: "Spam"
      })

    {:ok, appeal} = Eirinchan.Bans.create_appeal(ban.id, %{body: "Please review"})

    dashboard =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage")
      |> html_response(200)

    assert dashboard =~ "Report queue (1)"
    assert dashboard =~ "Ban appeals (1)"
    refute dashboard =~ "[reports]"
    refute dashboard =~ "[appeals]"

    reports_page =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/reports/browser")
      |> html_response(200)

    assert reports_page =~ "Report queue (1)"
    assert reports_page =~ "Spam"
    assert reports_page =~ "/#{board.uri}/"
    assert reports_page =~ ~s(class="report")
    assert reports_page =~ ~s(class="post-wrapper")
    assert reports_page =~ ~s(class="post op")
    assert reports_page =~ "/mod.php?/reports/#{report_id}/dismiss/"
    assert reports_page =~ ~s(class="controls op")

    dismiss_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> delete("/manage/reports/browser/#{report_id}")

    assert redirected_to(dismiss_conn) == "/manage/reports/browser"

    appeals_page =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/ban-appeals/browser")
      |> html_response(200)

    assert appeals_page =~ "Ban appeals (1)"
    assert appeals_page =~ "Please review"
    assert appeals_page =~ "/#{board.uri}/"

    resolve_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> patch("/manage/ban-appeals/browser/#{appeal.id}", %{
        "status" => "resolved",
        "resolution_note" => "Reviewed in browser"
      })

    assert redirected_to(resolve_conn) == "/manage/ban-appeals/browser"
  end

  test "browser ban form uses vichan-style length input and accepts compact durations", %{
    conn: conn
  } do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})

    other_board =
      board_fixture(%{uri: "leaf#{System.unique_integer([:positive])}", title: "Leaf"})

    thread = thread_fixture(board, %{body: "Thread body", ip_subnet: "198.51.100.7"})

    page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/boards/#{board.uri}/posts/#{thread.id}/ban/browser")
      |> html_response(200)

    assert page =~ ~s(name="ip")
    assert page =~ ~s(name="public_message")
    assert page =~ "USER WAS BANNED FOR THIS POST"
    assert page =~ ~s(name="length")
    assert page =~ "2d1h30m"
    assert page =~ ~s(id="ban-allboards")
    assert page =~ ~s(id="ban-board-#{board.uri}")
    assert page =~ ~s(id="ban-board-#{other_board.uri}")
    refute page =~ "Expires At"

    create_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> post("/manage/boards/#{board.uri}/posts/#{thread.id}/ban/browser", %{
        "ip" => "198.51.100.0/24",
        "reason" => "Spam",
        "length" => "1h",
        "board" => board.uri
      })

    assert redirected_to(create_conn) == "/#{board.uri}/res/#{thread.id}.html"

    [ban] = Eirinchan.Bans.list_bans(board_id: board.id)
    assert ban.ip_subnet == "198.51.100.0/24"
    assert DateTime.diff(ban.expires_at, DateTime.utc_now(), :second) in 3598..3602
  end

  test "browser IP history page supports notes and delete-by-ip actions", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})

    {:ok, thread, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{"body" => "green leaf", "subject" => "teaware", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{
          referer: "http://example.test/#{board.uri}/index.html",
          remote_ip: {198, 51, 100, 7}
        }
      )

    page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/boards/#{board.uri}/ip/198.51.100.7/browser")
      |> html_response(200)

    assert page =~ "IP History: 198.51.100.7"
    assert page =~ "green leaf"

    note_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> post("/manage/boards/#{board.uri}/ip/198.51.100.7/browser/notes", %{
        "body" => "Watch this IP"
      })

    assert redirected_to(note_conn) == "/manage/boards/#{board.uri}/ip/198.51.100.7/browser"

    note = hd(Eirinchan.Moderation.list_ip_notes("198.51.100.7", board_id: board.id))

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> patch("/manage/boards/#{board.uri}/ip/198.51.100.7/browser/notes/#{note.id}", %{
        "body" => "Updated note"
      })

    assert redirected_to(update_conn) == "/manage/boards/#{board.uri}/ip/198.51.100.7/browser"

    delete_posts_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> delete("/manage/boards/#{board.uri}/ip/198.51.100.7/browser/posts")

    assert redirected_to(delete_posts_conn) ==
             "/manage/boards/#{board.uri}/ip/198.51.100.7/browser"

    refute Eirinchan.Repo.get(Eirinchan.Posts.Post, thread.id)
  end

  test "janitor browser moderation pages cloak visible ip values", %{conn: conn} do
    janitor = moderator_fixture(%{role: "janitor"})
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})
    grant_board_access_fixture(janitor, board)

    {:ok, _thread, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{"body" => "green leaf", "subject" => "teaware", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{
          referer: "http://example.test/#{board.uri}/index.html",
          remote_ip: {198, 51, 100, 7}
        }
      )

    recent_page =
      conn
      |> login_moderator(janitor)
      |> get("/manage/recent-posts/browser")
      |> html_response(200)

    assert recent_page =~ ~s(class="post-wrapper")
    refute recent_page =~ "198.51.100.7"

    history_page =
      conn
      |> recycle()
      |> login_moderator(janitor)
      |> get("/manage/boards/#{board.uri}/ip/198.51.100.7/browser")
      |> html_response(200)

    assert history_page =~ "IP History: cloaked-"
    refute history_page =~ "IP History: 198.51.100.7"
  end

  test "browser moderation pages can move threads and replies", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    source_board = board_fixture(%{uri: "src"})
    target_board = board_fixture(%{uri: "dst"})
    source_thread = thread_fixture(source_board, %{body: "Thread to move"})
    _reply = reply_fixture(source_board, source_thread, %{body: "Thread reply"})
    reply_source_thread = thread_fixture(source_board, %{body: "Reply source"})
    target_thread = thread_fixture(target_board, %{body: "Reply target"})
    movable_reply = reply_fixture(source_board, reply_source_thread, %{body: "Reply to move"})

    move_thread_conn =
      conn
      |> login_moderator(moderator)
      |> patch("/manage/boards/#{source_board.uri}/threads/#{source_thread.id}/browser/move", %{
        "target_board_uri" => target_board.uri
      })

    assert redirected_to(move_thread_conn) == "/#{target_board.uri}/res/#{source_thread.id}.html"
    assert {:error, :not_found} = Eirinchan.Posts.get_thread(source_board, source_thread.id)

    assert {:ok, [_moved_thread, _moved_reply]} =
             Eirinchan.Posts.get_thread(target_board, source_thread.id)

    move_reply_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> patch("/manage/boards/#{source_board.uri}/posts/#{movable_reply.id}/browser/move", %{
        "target_board_uri" => target_board.uri,
        "target_thread_id" => Integer.to_string(target_thread.id)
      })

    assert redirected_to(move_reply_conn) == "/#{target_board.uri}/res/#{target_thread.id}.html"
    assert {:ok, [_thread]} = Eirinchan.Posts.get_thread(source_board, reply_source_thread.id)

    assert {:ok, [_target, moved_reply]} =
             Eirinchan.Posts.get_thread(target_board, target_thread.id)

    assert moved_reply.id == movable_reply.id
  end

  test "browser moderator messages page sends and replies to PMs", %{conn: conn} do
    sender = moderator_fixture(%{role: "admin"})
    recipient = moderator_fixture(%{role: "mod"})

    send_conn =
      conn
      |> login_moderator(sender)
      |> post("/manage/messages/browser", %{
        "recipient_id" => Integer.to_string(recipient.id),
        "subject" => "Heads up",
        "body" => "Check reports"
      })

    assert redirected_to(send_conn) == "/manage/messages/browser"

    inbox_page =
      conn
      |> recycle()
      |> login_moderator(recipient)
      |> get("/manage/messages/browser")
      |> html_response(200)

    assert inbox_page =~ "Moderator Messages"
    assert inbox_page =~ "Heads up"
    assert inbox_page =~ "Check reports"
    assert inbox_page =~ sender.username

    [message | _] = Eirinchan.Moderation.list_inbox(recipient)

    reply_conn =
      conn
      |> recycle()
      |> login_moderator(recipient)
      |> post("/manage/messages/browser", %{
        "recipient_id" => Integer.to_string(sender.id),
        "reply_to_id" => Integer.to_string(message.id),
        "body" => "Handled"
      })

    assert redirected_to(reply_conn) == "/manage/messages/browser"

    sender_page =
      conn
      |> recycle()
      |> login_moderator(sender)
      |> get("/manage/messages/browser")
      |> html_response(200)

    assert sender_page =~ "Handled"
    assert sender_page =~ recipient.username
  end

  test "browser edit post page matches vichan form structure and updates posts", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{uri: "editx", title: "EditX"})

    thread =
      thread_fixture(board, %{name: "Anon", email: "sage", subject: "Old", body: "Old body"})

    page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/boards/#{board.uri}/posts/#{thread.id}/edit/browser")
      |> html_response(200)

    assert page =~ "<h1>Edit post</h1>"
    assert page =~ ~s(name="name")
    assert page =~ ~s(name="email")
    assert page =~ ~s(name="subject")
    assert page =~ ~s(name="body")
    assert page =~ ~s(value="Update")
    refute page =~ "Back to Manage"

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> patch("/manage/boards/#{board.uri}/posts/#{thread.id}/edit/browser", %{
        "name" => "Changed",
        "email" => "noko",
        "subject" => "New",
        "body" => "New body"
      })

    assert redirected_to(update_conn) =~ "/#{board.uri}/res/#{thread.id}"
    assert {:ok, updated} = Eirinchan.Posts.get_post(board, thread.id)
    assert updated.name == "Changed"
    assert updated.email == "noko"
    assert updated.subject == "New"
    assert updated.body == "New body"
  end
end
