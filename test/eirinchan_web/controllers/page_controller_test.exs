defmodule EirinchanWeb.PageControllerTest do
  use EirinchanWeb.ConnCase
  import Ecto.Query

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.ThreadWatcher
  alias Eirinchan.PostOwnership
  alias Eirinchan.Repo
  alias Eirinchan.Settings
  alias Eirinchan.Statistics.Snapshot

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-page-themes-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  defp with_delimiters(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(.{3})(?=.)/, "\\1,")
    |> String.reverse()
  end

  test "GET /", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "tech", title: "Technology"})
    board_two = board_fixture(%{uri: "qa", title: "Question & Answer"})
    thread = thread_fixture(board, %{subject: "Opening", body: "Alpha bravo charlie delta"})
    reply_fixture(board, thread, %{body: "Recent reply body"})

    Repo.update_all(from(b in BoardRecord, where: b.id == ^board.id),
      set: [next_public_post_id: 336_961]
    )

    Repo.update_all(from(b in BoardRecord, where: b.id == ^board_two.id),
      set: [next_public_post_id: 25]
    )

    period_end = ~U[2026-07-18 04:00:00Z]

    %Snapshot{}
    |> Snapshot.changeset(%{
      period_start: DateTime.add(period_end, -3_600, :second),
      period_end: period_end,
      captured_at: period_end,
      counters: %{},
      daily_board_ppd: %{Integer.to_string(board.id) => 2},
      finalized: true
    })
    |> Repo.insert!()

    conn = get(conn, ~p"/")
    page = html_response(conn, 200)
    assert page =~ "Recent Posts"
    assert page =~ "Recent Images"
    assert page =~ "Latest Posts"
    assert page =~ "Stats"
    assert page =~ "Welcome"
    assert page =~ "Public Boards"
    assert page =~ ~s(src="/images/logo.svg")
    assert page =~ "Technology"
    assert page =~ "Recent reply body"
    assert page =~ ~s(href="/stylesheets/style.css)
    assert page =~ ~s(href="/recent.css)
    assert page =~ ~s(id="stylesheet" href="/stylesheets/yotsuba.css)
    assert page =~ ~s(data-stylesheet="yotsuba.css")
    assert page =~ ~s(name="eirinchan:active-page" content="index")
    assert page =~ ~s(name="eirinchan:board-name" content="")
    assert page =~ ~s(src="/main.js)
    assert page =~ ~s(name="csrf-token" content=")
    assert page =~ ~s(rel="icon" href="/images/logo.svg")

    assert page =~
             ~s(name="description" content="An imageboard powered by Eirinchan.")

    assert page =~ ~s(id="options_handler")
    assert page =~ ~s(id="style-select")
    assert page =~ "Tinyboard + vichan 5.2.2 +"
    assert page =~ ~s(href="https://github.com/eltanschauung/eirinchan-devel")

    document = Floki.parse_document!(page)

    assert document
           |> Floki.find(".box-wrap > .box > h2")
           |> Enum.map(&(&1 |> Floki.text() |> String.trim())) ==
             ["Welcome", "Public Boards", "Stats"]

    stats_rows = Floki.find(document, ".landing-stats .stats-table tbody tr")

    assert document
           |> Floki.find(".landing-stats .stats-table colgroup col")
           |> Enum.map(&Floki.attribute(&1, "class")) ==
             [["stats-label-column"], ["stats-value-column"]]

    assert Enum.map(stats_rows, fn row ->
             row |> Floki.find("th") |> Floki.text() |> String.trim()
           end) == ["Total Posts", "Posts This Week", "Active Content"]

    assert Enum.all?(stats_rows, &(length(Floki.find(&1, "th, td")) == 2))

    assert document
           |> Floki.find(".landing-recent-panels > .box")
           |> Enum.map(&(&1 |> Floki.find("h2") |> Floki.text() |> String.trim())) ==
             ["Recent Images", "Latest Posts"]

    assert document
           |> Floki.find(".public-boards tbody tr")
           |> Enum.map(fn row ->
             row
             |> Floki.find("td")
             |> Enum.map(&(&1 |> Floki.text() |> String.replace(~r/\s+/, " ") |> String.trim()))
           end) == [
             ["/tech/ - Technology", "2", "336,960"],
             ["/qa/ - Question & Answer", "0", "24"]
           ]

    expected_total_posts =
      Repo.one(
        from board in BoardRecord,
          select:
            coalesce(
              sum(fragment("GREATEST(COALESCE(?, 1) - 1, 0)", board.next_public_post_id)),
              0
            )
      )

    assert stats_rows
           |> List.first()
           |> Floki.find("td")
           |> Floki.text()
           |> String.trim() == with_delimiters(expected_total_posts)
  end

  test "GET / uses the configured website description", %{conn: conn} do
    description = "A custom & searchable imageboard description."

    assert {:ok, _config} =
             Settings.update_instance_config_from_json(
               Jason.encode!(%{website_description: description})
             )

    page = conn |> get("/") |> html_response(200)

    assert page =~
             ~s(name="description" content="A custom &amp; searchable imageboard description.")

    assert page =~
             ~s(property="og:description" content="A custom &amp; searchable imageboard description.")
  end

  test "robots.txt permits public crawling", %{conn: conn} do
    body = conn |> get("/robots.txt") |> response(200)
    assert body == "User-agent: *\nDisallow:\n"
  end

  test "GET / recent links prefer noko50 threads when available", %{conn: conn} do
    moderator_fixture()

    board =
      board_fixture(%{
        uri: "recentnoko#{System.unique_integer([:positive])}",
        title: "Recent Noko",
        config_overrides: %{noko50_min: 1}
      })

    thread = thread_fixture(board, %{subject: "Recent noko", body: "opening"})
    reply = reply_fixture(board, thread, %{body: "latest recent reply"})

    page =
      conn
      |> get("/")
      |> html_response(200)

    assert page =~
             ~s(href="/#{board.uri}/res/#{PublicIds.public_id(thread)}+50.html##{PublicIds.public_id(reply)}")
  end

  test "GET / renders RecentPosts homepage settings without replacing live panels", %{conn: conn} do
    moderator_fixture()

    {:ok, _theme} =
      Eirinchan.Themes.install_theme("recent", %{
        "title" => "Managed Home",
        "body" =>
          "<div class=\"box middle\"><h2>Managed introduction</h2><script>alert(1)</script></div>"
      })

    page = conn |> get("/") |> html_response(200)

    assert page =~ "<title>Managed Home</title>"
    assert page =~ "Managed introduction"
    assert page =~ "Recent Images"
    assert page =~ "Latest Posts"
    assert page =~ "Stats"
    assert page =~ "Public Boards"
    refute page =~ "alert(1)"
    refute page =~ "What is bnat?"
  end

  test "GET / Public Boards respects Recent theme exclusions", %{conn: conn} do
    moderator_fixture()
    included = board_fixture(%{uri: "included", title: "Included Board"})
    excluded = board_fixture(%{uri: "excluded", title: "Excluded Board"})
    thread_fixture(included, %{body: "Included activity"})
    thread_fixture(excluded, %{body: "Excluded activity"})

    {:ok, _theme} =
      Eirinchan.Themes.install_theme("recent", %{
        "body" =>
          "<div class=\"box middle\"><h2>Before boards</h2></div>{{public_boards}}<div class=\"box middle\"><h2>After boards</h2></div>",
        "exclude" => excluded.uri
      })

    page = conn |> get("/") |> html_response(200)
    document = Floki.parse_document!(page)

    assert document
           |> Floki.find(".box-wrap > .box > h2")
           |> Enum.map(&(&1 |> Floki.text() |> String.trim())) ==
             ["Before boards", "Public Boards", "Stats", "After boards"]

    assert page =~ "/#{included.uri}/ - #{included.title}"
    refute page =~ "/#{excluded.uri}/ - #{excluded.title}"
  end

  test "Latest Posts uses board subtitles by default and URI labels when disabled", %{conn: conn} do
    moderator_fixture()

    board =
      board_fixture(%{
        uri: "labels#{System.unique_integer([:positive])}",
        title: "Board title label",
        subtitle: "Board subtitle label"
      })

    thread_fixture(board, %{body: "Label setting post"})

    default_page = conn |> get("/") |> html_response(200) |> Floki.parse_document!()
    default_latest_posts = default_page |> Floki.find(".landing-recent-posts") |> Floki.text()

    assert default_latest_posts =~ "Board subtitle label"
    refute default_latest_posts =~ "/#{board.uri}/"

    settings =
      "recent"
      |> Eirinchan.Themes.theme_settings()
      |> Map.put("use_board_subtitle", false)

    assert {:ok, _theme} = Eirinchan.Themes.install_theme("recent", settings)

    uri_page = conn |> recycle() |> get("/") |> html_response(200) |> Floki.parse_document!()
    uri_latest_posts = uri_page |> Floki.find(".landing-recent-posts") |> Floki.text()

    assert uri_latest_posts =~ "/#{board.uri}/"
    refute uri_latest_posts =~ "Board subtitle label"
  end

  test "GET / renders without a browser installer when no admin exists", %{conn: conn} do
    page = conn |> get(~p"/") |> html_response(200)
    refute page =~ "/setup"
  end

  test "browser installation endpoints do not exist", %{conn: conn} do
    assert conn |> get("/setup") |> response(404)
    assert conn |> recycle() |> post("/setup", %{}) |> response(404)
  end

  test "GET /news renders public blotter entries", %{conn: conn} do
    page_author = moderator_fixture(%{username: "pageeditor"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "faq",
        title: "FAQ",
        body: "Questions",
        mod_user_id: page_author.id
      })

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        news_blotter_entries: [
          %{date: "03/20/26", message: "Board online"},
          %{date: "03/19/26", message: "Launch"}
        ]
      })

    conn = get(conn, ~p"/news")
    page = html_response(conn, 200)
    assert page =~ "News"
    assert page =~ "PSA Blotter"
    assert page =~ "Launch"
    assert page =~ "Board online"
    assert page =~ "03/20/26"
    assert page =~ ~s(class="boardlist")
    assert page =~ ~s(name="eirinchan:active-page" content="news")
    assert page =~ ~s(name="eirinchan:board-name" content="")
    assert page =~ "Tinyboard + vichan 5.2.2 +"
    assert page =~ ~s(href="https://github.com/eltanschauung/eirinchan-devel")
  end

  test "public pages select desktop and mobile boardlists independently", %{conn: conn} do
    moderator_fixture()
    board_fixture(%{uri: "deskboard", title: "Desktop Board"})
    board_fixture(%{uri: "phoneboard", title: "Mobile Board"})

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        boardlist: %{
          desktop: [["deskboard"], %{"Home" => "/"}],
          mobile: [["phoneboard"], %{"Home" => "/"}]
        }
      })

    desktop_page =
      conn
      |> get("/news")
      |> html_response(200)

    assert desktop_page =~ ~s(href="/deskboard/index.html")
    refute desktop_page =~ ~s(href="/phoneboard/index.html")

    mobile_page =
      conn
      |> recycle()
      |> put_req_header(
        "user-agent",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
      )
      |> get("/news")
      |> html_response(200)

    assert mobile_page =~ ~s(href="/phoneboard/index.html")
    refute mobile_page =~ ~s(href="/deskboard/index.html")
  end

  test "unknown public paths render the shared 404 page with fixed yotsuba styling", %{conn: conn} do
    moderator_fixture()
    board_fixture(%{uri: "bant", title: "International Random"})
    board_fixture(%{uri: "qa", title: "Question & Answer"})

    page =
      conn
      |> get("/totally/missing/page")
      |> html_response(404)

    assert page =~ "Error 404"
    assert page =~ "Not found. What is blud doing?"
    assert page =~ "/error_pages/sanae.png"
    assert page =~ ~s(class="boardlist")
    assert page =~ ~s(href="/stylesheets/style.css)
    assert page =~ ~s(id="stylesheet" href="/stylesheets/yotsuba.css)
    assert page =~ ~s(data-stylesheet="yotsuba.css")
    refute page =~ ~s(id="style-select")
  end

  test "GET / returns an etag and honors if-none-match", %{conn: conn} do
    moderator_fixture()

    board =
      board_fixture(%{uri: "etaghome#{System.unique_integer([:positive])}", title: "ETag Home"})

    thread = thread_fixture(board, %{subject: "Opening", body: "Alpha bravo charlie delta"})
    reply_fixture(board, thread, %{body: "Recent reply body"})

    first_conn = get(conn, "/")
    assert first_conn.status == 200

    etag =
      first_conn
      |> get_resp_header("etag")
      |> List.first()

    assert is_binary(etag)
    assert get_resp_header(first_conn, "cache-control") == ["private, no-cache"]

    second_conn =
      conn
      |> recycle()
      |> put_req_header("if-none-match", etag)
      |> get("/")

    assert second_conn.status == 304
    assert second_conn.resp_body == ""
    assert get_resp_header(second_conn, "etag") == [etag]
  end

  test "forced_theme overrides visitor theme cookies and hides the style selector", %{conn: conn} do
    moderator_fixture()

    board =
      board_fixture(%{
        uri: "forcedtheme#{System.unique_integer([:positive])}",
        title: "Forced Theme"
      })

    thread = thread_fixture(board, %{subject: "Opening", body: "Alpha bravo charlie delta"})
    reply_fixture(board, thread, %{body: "Recent reply body"})
    original_config = Eirinchan.Settings.current_instance_config()

    on_exit(fn ->
      :ok = Eirinchan.Settings.persist_instance_config(original_config)
    end)

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        forced_theme: "aya"
      })

    page =
      conn
      |> put_req_cookie("theme", "tomorrow")
      |> get("/")
      |> html_response(200)

    assert page =~ ~s(id="stylesheet" href="/stylesheets/aya.css)
    assert page =~ ~s(data-stylesheet="aya.css")
    refute page =~ ~s(id="style-select")
  end

  test "board forced_theme overrides board theme cookies and hides the style selector on that board",
       %{conn: conn} do
    moderator_fixture()

    board =
      board_fixture(%{
        uri: "boardforced#{System.unique_integer([:positive])}",
        title: "Board Forced Theme",
        config_overrides: %{force_theme: "bluearchive"}
      })

    thread = thread_fixture(board, %{subject: "Opening", body: "Alpha bravo charlie delta"})
    reply_fixture(board, thread, %{body: "Recent reply body"})

    page =
      conn
      |> put_req_cookie("board_themes", ~s({"#{board.uri}":"tomorrow"}))
      |> get("/#{board.uri}/")
      |> html_response(200)

    assert page =~ ~s(id="stylesheet" href="/stylesheets/bluearchive.css)
    assert page =~ ~s(data-stylesheet="bluearchive.css")
    refute page =~ ~s(id="style-select")
  end

  test "rules page renders global message stats placeholders and line breaks", %{conn: conn} do
    moderator_fixture()

    board =
      board_fixture(%{uri: "gmstats#{System.unique_integer([:positive])}", title: "GM Stats"})

    thread = thread_fixture(board, %{body: "seed"})
    reply_fixture(board, thread, %{body: "recent"})

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        global_message:
          "Visitors in the last 10 minutes: {stats.users_10minutes}\\nPPH: {stats.posts_perhour}"
      })

    page =
      conn
      |> get("/rules")
      |> html_response(200)

    assert page =~ "Visitors in the last 10 minutes:"
    assert page =~ "PPH:"
    assert page =~ "<br />"
    refute page =~ "{stats.users_10minutes}"
    refute page =~ "{stats.posts_perhour}"
  end

  test "faq and formatting suppress the global message and preserve page-specific layout",
       %{
         conn: conn
       } do
    moderator_fixture()

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        global_message:
          "Visitors in the last 10 minutes: {stats.users_10minutes}\\nPPH: {stats.posts_perhour}"
      })

    faq_page =
      conn
      |> get("/faq")
      |> html_response(200)

    refute faq_page =~ "Visitors in the last 10 minutes:"

    formatting_page =
      conn
      |> recycle()
      |> get("/formatting")
      |> html_response(200)

    refute formatting_page =~ "Visitors in the last 10 minutes:"
  end

  test "custom pages render global message through the shared blotter renderer", %{conn: conn} do
    author = moderator_fixture(%{username: "pagewriter"})

    board =
      board_fixture(%{uri: "customgm#{System.unique_integer([:positive])}", title: "Custom GM"})

    thread = thread_fixture(board, %{body: "seed"})
    reply_fixture(board, thread, %{body: "recent"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "help-gm",
        title: "Help",
        body: "How to post",
        mod_user_id: author.id
      })

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        global_message: "<i>Visitors:</i> {stats.users_10minutes}\\nPPH: {stats.posts_perhour}"
      })

    page = conn |> get("/pages/help-gm") |> html_response(200)

    assert page =~ "<i>Visitors:</i>"
    assert page =~ "PPH:"
    assert page =~ "<br />"
    refute page =~ "{stats.users_10minutes}"
    refute page =~ "{stats.posts_perhour}"
  end

  test "GET /pages/:slug renders a custom page", %{conn: conn} do
    author = moderator_fixture(%{username: "pagewriter"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "help",
        title: "Help",
        body: "How to post",
        mod_user_id: author.id
      })

    conn = get(conn, "/pages/help")
    page = html_response(conn, 200)
    assert page =~ "Help"
    assert page =~ "How to post"
    assert page =~ "pagewriter"
  end

  test "GET /pages/:slug sanitizes dangerous custom page html", %{conn: conn} do
    author = moderator_fixture(%{username: "sanitizer"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "safe-help",
        title: "Safe Help",
        body:
          ~s|<div onclick="alert(1)"><script>alert(1)</script><a href="javascript:alert(1)">Bad</a><img src="/ok.png" onerror="alert(1)"></div>|,
        mod_user_id: author.id
      })

    page = conn |> get("/pages/safe-help") |> html_response(200)

    refute page =~ "<script>alert(1)</script>"
    refute page =~ "onclick="
    refute page =~ "onerror="
    refute page =~ "href=\"javascript:alert(1)\""
    assert page =~ ~s(href="#")
    assert page =~ ~s(src="/ok.png")
  end

  test "GET /faq renders the generic FAQ page", %{conn: conn} do
    moderator_fixture()

    page =
      conn
      |> get("/faq")
      |> html_response(200)

    assert page =~ "What is this site?"
    assert page =~ "How do I post?"
    assert page =~ ~s(href="/recent.css)
  end

  test "GET /rules renders the generic rules page", %{conn: conn} do
    moderator_fixture()

    page =
      conn
      |> get("/rules")
      |> html_response(200)

    assert page =~ "Global rules"
    assert page =~ "Contact"
    assert page =~ ~s(href="/recent.css")
  end

  test "GET /rules normalizes stored full html overrides into the shared shell", %{conn: conn} do
    moderator_fixture()
    author = moderator_fixture(%{username: "ruleseditor"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "rules",
        title: "Rules",
        body:
          "<!doctype html><html><body><header><h1>ignored</h1></header><div class=\"box-wrap faq-page-shell rules-page-shell\"><div class=\"box middle\"><h2><i>Stored Rules</i></h2></div></div><hr><footer>ignored</footer></body></html>",
        mod_user_id: author.id
      })

    rules_conn = get(conn, "/rules")
    html = response(rules_conn, 200)

    assert html =~ "Stored Rules"
    assert html =~ ~s(class="boardlist")
    refute html =~ "<header><h1>ignored</h1></header>"
    refute html =~ "Updated by ruleseditor"
  end

  test "GET /faq normalizes stored full html overrides into the shared shell", %{conn: conn} do
    author = moderator_fixture(%{username: "faqeditor"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "faq",
        title: "FAQ",
        body: "<!doctype html><html><body><h1>Stored FAQ</h1></body></html>",
        mod_user_id: author.id
      })

    faq_conn = get(conn, "/faq")

    assert response(faq_conn, 200) =~ "<h1>Stored FAQ</h1>"
    assert response(faq_conn, 200) =~ ~s(class="boardlist")
    assert response(faq_conn, 200) =~ ~s(id="options-link")
  end

  test "GET /watcher/fragment returns fragment without layout chrome", %{conn: conn} do
    moderator_fixture()

    conn =
      conn
      |> put_req_header("x-requested-with", "XMLHttpRequest")
      |> get("/watcher/fragment")

    html = response(conn, 200)

    assert html =~ ~s(class="watcher-page")
    refute html =~ "<!doctype html>"
    refute html =~ ~s(class="boardlist bottom")
    refute html =~ ~s(class="styles")
  end

  test "GET /formatting renders generic formatting help", %{conn: conn} do
    moderator_fixture()

    page =
      conn
      |> get("/formatting")
      |> html_response(200)

    assert page =~ "Formatting"
    assert page =~ "creates a quote"
    assert page =~ "Configured stickers"
    assert page =~ "No stickers are configured."
    assert page =~ "formatting-sticker-columns"
  end

  test "rules preserve numbered headings and use the configured contact email", %{conn: conn} do
    moderator_fixture()

    {:ok, _config} =
      Settings.update_instance_config_from_json(
        Jason.encode!(%{contact_email: "rules@instance.test"})
      )

    page = get(conn, "/rules") |> html_response(200)

    assert page =~ "Do not post content that is illegal"
    assert page =~ "Do not disrupt the service"
    assert page =~ ~s(href="mailto:rules@instance.test")
  end

  test "GET /formatting normalizes stored full html overrides into the shared shell", %{
    conn: conn
  } do
    author = moderator_fixture(%{username: "formattingeditor"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "formatting",
        title: "Formatting",
        body: "<!doctype html><html><body><h1>Stored Formatting</h1></body></html>",
        mod_user_id: author.id
      })

    formatting_conn = get(conn, "/formatting")

    html = response(formatting_conn, 200)

    assert html =~ "<h1>Stored Formatting</h1>"
    assert html =~ ~s(class="boardlist")
    assert html =~ ~s(id="options-link")
    refute html =~ "Updated by formattingeditor"
    assert get_resp_header(formatting_conn, "content-type") == ["text/html; charset=utf-8"]
  end

  test "GET /pages/faq uses the FAQ template and stored body when the page exists", %{conn: conn} do
    author = moderator_fixture(%{username: "faqwriter"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "faq",
        title: "FAQ",
        body:
          ~s(<div class="box-wrap faq-page-shell"><div class="box middle"><div class="content">Copied FAQ</div></div></div>),
        mod_user_id: author.id
      })

    page =
      conn
      |> get("/pages/faq")
      |> html_response(200)

    assert page =~ "Copied FAQ"
    assert page =~ "Ask questions, get answers."
  end

  test "GET /catalog renders a global catalog across boards", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    moderator_fixture()
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})

    other_board =
      board_fixture(%{uri: "meta#{System.unique_integer([:positive])}", title: "Meta"})

    quoted_thread = thread_fixture(board, %{subject: "Tea thread", body: "Green tea"})

    thread_fixture(other_board, %{
      subject: "Meta thread",
      body: ">>#{PublicIds.public_id(quoted_thread)} Board ops"
    })

    page =
      conn
      |> get("/catalog")
      |> html_response(200)

    assert page =~ "Global Catalog"
    assert page =~ "Tea thread"
    assert page =~ "Meta thread"
    assert page =~ "&gt;&gt;#{PublicIds.public_id(quoted_thread)}"
  end

  test "GET /ukko renders aggregated board threads", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})
    thread_fixture(board, %{subject: "Tea ukko", body: "Ukko body"})

    page =
      conn
      |> get("/ukko")
      |> html_response(200)

    assert page =~ "Ukko"
    assert page =~ "Tea ukko"
    assert page =~ board.uri
  end

  test "GET /ukko orders threads by recent sage activity and uses plain board labels", %{
    conn: conn
  } do
    moderator_fixture()
    board = board_fixture(%{uri: "sage#{System.unique_integer([:positive])}", title: "Sage"})

    saged_thread = thread_fixture(board, %{subject: "Saged latest", body: "sage body"})
    bumped_thread = thread_fixture(board, %{subject: "Bumped older", body: "bump body"})

    old_time = ~U[2026-03-19 14:00:00Z]
    mid_time = ~U[2026-03-19 15:00:00Z]
    late_time = ~U[2026-03-19 16:00:00Z]

    Repo.update_all(from(p in Eirinchan.Posts.Post, where: p.id == ^saged_thread.id),
      set: [inserted_at: old_time, bump_at: old_time]
    )

    Repo.update_all(from(p in Eirinchan.Posts.Post, where: p.id == ^bumped_thread.id),
      set: [inserted_at: mid_time, bump_at: mid_time]
    )

    {:ok, _reply, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{
          "thread" => Integer.to_string(PublicIds.public_id(saged_thread)),
          "email" => "sage",
          "body" => "latest sage reply",
          "post" => "New Reply"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    Repo.update_all(
      from(
        p in Eirinchan.Posts.Post,
        where: p.thread_id == ^saged_thread.id and p.email == "sage"
      ),
      set: [inserted_at: late_time]
    )

    page =
      conn
      |> get("/ukko")
      |> html_response(200)

    assert page =~ ~s(class="unimportant2 overboard-board-label">/#{board.uri}/</small>)
    refute page =~ ~s(<h2><a href="/#{board.uri}">/#{board.uri}/</a></h2>)

    {saged_index, _} = :binary.match(page, "Saged latest")
    {bumped_index, _} = :binary.match(page, "Bumped older")
    assert saged_index < bumped_index
  end

  test "GET /ukko uses shared browser post hooks for watcher and post controls", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "hooks#{System.unique_integer([:positive])}", title: "Hooks"})
    thread = thread_fixture(board, %{subject: "Hooks thread", body: "opening"})
    _reply = reply_fixture(board, thread, %{body: "reply body"})

    page =
      conn
      |> get("/ukko")
      |> html_response(200)

    assert page =~ ~s(form name="postcontrols" action="/post.php" method="post" hidden)

    assert page =~ ~s(data-thread-watch)
    assert page =~ ~s(data-thread-id="#{PublicIds.public_id(thread)}")

    assert page =~ ~s(class="thread-top-controls")
    assert length(Regex.scan(~r/class="post-btn" title="Post menu"/, page)) >= 2
  end

  test "GET /ukko renders visible timestamps using the browser timezone cookie", %{conn: conn} do
    moderator_fixture()

    board =
      board_fixture(%{uri: "ukkozone#{System.unique_integer([:positive])}", title: "Ukko Zone"})

    thread = thread_fixture(board, %{subject: "Ukko timezone", body: "Ukko body"})
    inserted_at = ~U[2026-03-13 12:00:00Z]

    from(post in Eirinchan.Posts.Post, where: post.id == ^thread.id)
    |> Repo.update_all(set: [inserted_at: inserted_at])

    page =
      conn
      |> put_req_cookie("timezone_offset", "-180")
      |> get("/ukko")
      |> html_response(200)

    assert page =~ "03/13/26 (Fri) 09:00:00"
    refute page =~ "03/13/26 (Fri) 12:00:00"
  end

  test "configurable overboard uri redirects /ukko and renders at configured path", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "okuutest#{System.unique_integer([:positive])}", title: "Okuu"})
    thread_fixture(board, %{subject: "Configured ukko", body: "Cross-board body"})

    assert {:ok, _theme} =
             Eirinchan.Themes.install_theme("ukko", %{
               "uri" => "okuu",
               "title" => "Okuu",
               "subtitle" => "Cross-board thread index"
             })

    redirect_conn = get(conn, "/ukko")
    assert redirected_to(redirect_conn) == "/okuu"

    page =
      build_conn()
      |> get("/okuu")
      |> html_response(200)

    assert page =~ "Okuu"
    assert page =~ "Configured ukko"
    assert page =~ board.uri
  end

  test "overboard paginates and shows moderation controls for signed-in staff", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{uri: "pages#{System.unique_integer([:positive])}", title: "Pages"})
    second_thread = thread_fixture(board, %{subject: "Second overboard page", body: "two"})
    first_thread = thread_fixture(board, %{subject: "First overboard page", body: "one"})

    assert {:ok, _theme} =
             Eirinchan.Themes.install_theme("ukko", %{
               "thread_limit" => "1"
             })

    page_one =
      conn
      |> login_moderator(moderator)
      |> get("/ukko")
      |> html_response(200)

    assert page_one =~ "First overboard page"
    refute page_one =~ "Second overboard page"
    assert page_one =~ ~s(data-overboard-pages)
    assert page_one =~ ~s(data-next-link="/ukko/2.html")
    assert page_one =~ ~s(src="/main.js")
    assert page_one =~ ~s(name="delete_#{PublicIds.public_id(first_thread)}")

    assert page_one =~
             ~s(data-secure-href="/mod.php?/#{board.uri}/delete/#{PublicIds.public_id(first_thread)}/)

    assert page_one =~ ~s(class="controls op")

    page_two =
      build_conn()
      |> login_moderator(moderator)
      |> get("/ukko/2.html")
      |> html_response(200)

    assert page_two =~ "Second overboard page"
    refute page_two =~ "First overboard page"
    assert page_two =~ ~s([<a class="selected">2</a>])
    assert page_two =~ ~s(name="delete_#{PublicIds.public_id(second_thread)}")
  end

  test "GET /recent renders recent posts across boards", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})
    thread = thread_fixture(board, %{subject: "Recent thread", body: "Opening"})
    reply_fixture(board, thread, %{body: "Recent reply"})

    page =
      conn
      |> get("/recent")
      |> html_response(200)

    assert page =~ "Recent Posts"
    assert page =~ "Recent Images"
    assert page =~ "This imageboard is powered by Eirinchan."
    assert page =~ "Recent reply"
    assert page =~ board.title
    assert page =~ ~s(class="boardlist")
    assert page =~ ~s(href="/recent.css)
  end

  test "home and recent inherit the primary board automatic dark default", %{conn: conn} do
    moderator_fixture()

    board_fixture(%{
      uri: "bant",
      title: "International Random",
      config_overrides: %{default_theme: "yotsuba", default_theme_dark: "tomorrow"}
    })

    for path <- ["/", "/recent"] do
      light_page =
        conn
        |> recycle()
        |> get(path)
        |> html_response(200)

      assert light_page =~ ~s(id="stylesheet" href="/stylesheets/yotsuba.css)
      assert light_page =~ ~s(data-auto-theme-light-name="yotsuba")
      assert light_page =~ ~s(data-auto-theme-dark-name="tomorrow")
      assert light_page =~ ~s(src="/js/theme-bootstrap.js)

      dark_page =
        conn
        |> recycle()
        |> put_req_cookie("eirinchan_color_scheme", "dark")
        |> get(path)
        |> html_response(200)

      assert dark_page =~ ~s(id="stylesheet" href="/stylesheets/tomorrow.css)
      assert dark_page =~ ~s(data-stylesheet="tomorrow.css")
      assert dark_page =~ ~s(data-auto-theme-light-name="yotsuba")
      assert dark_page =~ ~s(data-auto-theme-dark-name="tomorrow")
    end
  end

  test "GET / recent images include video posts with thumbnails", %{conn: conn} do
    moderator_fixture()

    board =
      board_fixture(%{
        uri: "recentvid#{System.unique_integer([:positive])}",
        title: "Recent Video"
      })

    thread = thread_fixture(board, %{subject: "Recent video thread", body: "Opening"})
    reply = reply_fixture(board, thread, %{body: "Recent video reply"})

    Repo.update_all(
      from(post in Eirinchan.Posts.Post, where: post.id == ^reply.id),
      set: [
        file_type: "video/webm",
        thumb_path: "/#{board.uri}/thumb/video-thumb.jpg",
        image_width: 640,
        image_height: 360
      ]
    )

    page =
      conn
      |> get("/")
      |> html_response(200)

    assert page =~ "/#{board.uri}/thumb/video-thumb.jpg"
  end

  test "GET /sitemap.xml renders board and thread urls", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    moderator_fixture()
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})
    thread = thread_fixture(board, %{subject: "Mapped", body: "XML body"})

    xml =
      conn
      |> get("/sitemap.xml")
      |> response(200)

    assert xml =~ "<?xml version=\"1.0\""
    assert xml =~ "/#{board.uri}</loc>"
    assert xml =~ "/#{board.uri}/catalog.html</loc>"
    assert xml =~ "/#{board.uri}/res/#{PublicIds.public_id(thread)}"
    assert xml =~ "<lastmod>"
    assert xml =~ "<changefreq>hourly</changefreq>"
  end

  test "GET /pages/feedback uses the feedback page constructor and form", %{conn: conn} do
    author = moderator_fixture(%{username: "feedbackwriter"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "feedback",
        title: "Feedback",
        body: "Tell us what broke",
        mod_user_id: author.id
      })

    page =
      conn
      |> get("/pages/feedback")
      |> html_response(200)

    assert page =~ "Tell us what broke"
    assert page =~ "Send Feedback"
    assert page =~ ~s(class="feedback-textarea")
  end

  test "public custom pages carry over the selected theme stylesheet", %{conn: conn} do
    moderator_fixture()

    page =
      conn
      |> put_req_cookie("theme", "eientei1")
      |> get("/faq")
      |> html_response(200)

    assert page =~ ~s(id="stylesheet" href="/stylesheets/eientei1.css)
    assert page =~ ~s(data-stylesheet="eientei1.css")
  end

  test "renders watcher page with watched threads", %{conn: conn} do
    moderator_fixture()

    board =
      Eirinchan.BoardsFixtures.board_fixture(%{
        uri: "watchtest",
        title: "Watch Test",
        config_overrides: %{noko50_min: 0}
      })

    thread = Eirinchan.PostsFixtures.thread_fixture(board, %{body: "watch body"})
    token = browser_token("page-watches")

    assert {:ok, _} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id, %{
               last_seen_post_id: thread.id
             })

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> get(~p"/watcher")

    body = html_response(conn, 200)
    assert body =~ "Thread Watcher"
    assert body =~ "/watchtest/ - Opening subject"
    assert body =~ "[Unwatch]"
    refute body =~ ~s(href="/watchtest/res/#{PublicIds.public_id(thread)}.html")
    assert body =~ ~s(href="/watchtest/res/#{PublicIds.public_id(thread)}+50.html")
  end

  test "renders watcher unread counts", %{conn: conn} do
    moderator_fixture()
    board = Eirinchan.BoardsFixtures.board_fixture(%{uri: "watchunread", title: "Watch Unread"})
    thread = Eirinchan.PostsFixtures.thread_fixture(board, %{body: "watch body"})
    _reply = Eirinchan.PostsFixtures.reply_fixture(board, thread, %{body: "Unread reply"})
    token = browser_token("watcher-unread")

    assert {:ok, _} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id, %{
               last_seen_post_id: thread.id
             })

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> get(~p"/watcher")

    body = html_response(conn, 200)
    assert body =~ "unread: 1"
  end

  test "renders watcher fragment without page chrome", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "watchfrag", title: "Watch Frag"})
    thread = thread_fixture(board, %{subject: "Watched Thread", body: "Opening"})
    token = browser_token("watcher-fragment")

    {:ok, _watch} =
      ThreadWatcher.watch_thread(token, board.uri, thread.id, %{last_seen_post_id: thread.id})

    body =
      conn
      |> put_req_cookie("browser_token", token)
      |> get("/watcher/fragment")
      |> html_response(200)

    assert body =~ "watcher-page"
    assert body =~ "Watched Thread"
    refute body =~ "<header>"
    refute body =~ "Thread Watcher"
  end

  test "watcher fragment shows unread you counts", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "watchyoufrag", title: "Watch You Frag"})
    thread = thread_fixture(board, %{subject: "Watched Thread", body: "Opening"})
    owned_reply = reply_fixture(board, thread, %{body: "Owned"})

    _citing_reply =
      reply_fixture(board, thread, %{body: ">>#{PublicIds.public_id(owned_reply)} cited"})

    token = browser_token("watcher-you-fragment")

    {:ok, _} = PostOwnership.record(token, owned_reply.id)

    {:ok, _watch} =
      ThreadWatcher.watch_thread(token, board.uri, thread.id, %{last_seen_post_id: owned_reply.id})

    body =
      conn
      |> put_req_cookie("browser_token", token)
      |> get("/watcher/fragment")
      |> html_response(200)

    assert body =~ "watcher-you-count"
    assert body =~ "(You)s:"
    assert body =~ "(1)"
    assert body =~ "replies-quoting-you"
  end

  test "public pages expose watcher count for top bar", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "watchhome", title: "Watch Home"})
    thread = thread_fixture(board, %{body: "Watcher home thread"})
    token = browser_token("home-watch")

    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, board.uri, thread.id)

    page =
      conn
      |> put_req_cookie("browser_token", token)
      |> get("/")
      |> html_response(200)

    assert page =~ ~s(data-watcher-count="1")
    assert page =~ ~s(name="eirinchan:watcher-count" content="1")
  end

  test "public pages expose watcher you count for top bar", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "watchyouhome", title: "Watch You Home"})
    thread = thread_fixture(board, %{body: "Watcher home thread"})
    owned_reply = reply_fixture(board, thread, %{body: "Owned"})

    _citing_reply =
      reply_fixture(board, thread, %{body: ">>#{PublicIds.public_id(owned_reply)} cited"})

    token = browser_token("home-watch-you")

    {:ok, _} = PostOwnership.record(token, owned_reply.id)

    assert {:ok, _watch} =
             ThreadWatcher.watch_thread(token, board.uri, thread.id, %{
               last_seen_post_id: owned_reply.id
             })

    page =
      conn
      |> put_req_cookie("browser_token", token)
      |> get("/")
      |> html_response(200)

    assert page =~ ~s(data-watcher-you-count="1")
    assert page =~ ~s(name="eirinchan:watcher-you-count" content="1")
  end
end
