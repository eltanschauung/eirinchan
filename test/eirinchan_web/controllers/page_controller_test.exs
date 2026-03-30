defmodule EirinchanWeb.PageControllerTest do
  use EirinchanWeb.ConnCase
  import Ecto.Query

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.ThreadWatcher
  alias Eirinchan.PostOwnership
  alias Eirinchan.Repo

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

    Repo.update_all(from(b in BoardRecord, where: b.id == ^board.id), set: [next_public_post_id: 336_961])
    Repo.update_all(from(b in BoardRecord, where: b.id == ^board_two.id), set: [next_public_post_id: 25])

    conn = get(conn, ~p"/")
    page = html_response(conn, 200)
    assert page =~ "Recent Posts"
    assert page =~ "Recent Images"
    assert page =~ "Latest Posts"
    assert page =~ "Stats"
    assert page =~ "What is bnat?"
    assert page =~ "Whales are learning facts!"
    assert page =~ ~s(src="/site_logo.png")
    assert page =~ ~s(src="/whales.jpg")
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
    assert page =~ ~s(id="options_handler")
    assert page =~ ~s(id="style-select")
    assert page =~ "Tinyboard + vichan 5.2.2 +"
    assert page =~ ~s(href="https://github.com/username/eirinchan-v1")

    expected_total_posts =
      Repo.one(
        from board in BoardRecord,
          select: coalesce(sum(fragment("GREATEST(COALESCE(?, 1) - 1, 0)", board.next_public_post_id)), 0)
      )

    assert page =~ "Total posts: #{with_delimiters(expected_total_posts)}"
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

  test "GET / redirects to setup when no admin exists", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/setup"
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
    assert page =~ ~s(href="https://github.com/username/eirinchan-v1")
  end

  test "GET / returns an etag and honors if-none-match", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "etaghome#{System.unique_integer([:positive])}", title: "ETag Home"})
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

  test "site-wide public static pages render global message stats placeholders and line breaks", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "gmstats#{System.unique_integer([:positive])}", title: "GM Stats"})
    thread = thread_fixture(board, %{body: "seed"})
    reply_fixture(board, thread, %{body: "recent"})

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        global_message:
          "Visitors in the last 10 minutes: {stats.users_10minutes}\\nPPH: {stats.posts_perhour}"
      })

    page =
      conn
      |> get("/faq")
      |> html_response(200)

    assert page =~ "Visitors in the last 10 minutes:"
    assert page =~ "PPH:"
    assert page =~ "<br />"
    refute page =~ "{stats.users_10minutes}"
    refute page =~ "{stats.posts_perhour}"
  end

  test "custom pages render global message through the shared blotter renderer", %{conn: conn} do
    author = moderator_fixture(%{username: "pagewriter"})
    board = board_fixture(%{uri: "customgm#{System.unique_integer([:positive])}", title: "Custom GM"})
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

  test "GET /faq renders the copied FAQ page", %{conn: conn} do
    moderator_fixture()

    page =
      conn
      |> get("/faq")
      |> html_response(200)

    assert page =~ "What is bnat?"
    assert page =~ "What are those flag things?"
    assert page =~ "/faq/output_canvas.png"
    assert page =~ "/faq/whale.jpg"
    assert page =~ ~s(href="/faq/recent.css)
  end

  test "GET /rules renders the copied rules page", %{conn: conn} do
    moderator_fixture()

    page =
      conn
      |> get("/rules")
      |> html_response(200)

    assert page =~ "What are the Rules?"
    assert page =~ "/bant/ - International/Random"
    assert page =~ "What if i'm banned?"
    assert page =~ ~s(src="/site_logo2.png")
    assert page =~ ~s(href="/faq/recent.css")
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
    assert html =~ ~s(src="/site_logo2.png")
    refute html =~ "<header><h1>ignored</h1></header>"
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

  test "GET /formatting renders copied formatting page", %{conn: conn} do
    moderator_fixture()

    page =
      conn
      |> get("/formatting")
      |> html_response(200)

    assert page =~ "Formatting"
    assert page =~ "**do this to spoiler text**"
    assert page =~ "Whalestickers"
    assert page =~ ":gojo:"
    assert page =~ "Let's bring /bnat/ to life with tranimals and babies!"
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

    assert response(formatting_conn, 200) =~ "<h1>Stored Formatting</h1>"
    assert response(formatting_conn, 200) =~ ~s(class="boardlist")
    assert response(formatting_conn, 200) =~ ~s(id="options-link")
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

    thread_fixture(board, %{subject: "Tea thread", body: "Green tea"})
    thread_fixture(other_board, %{subject: "Meta thread", body: "Board ops"})

    page =
      conn
      |> get("/catalog")
      |> html_response(200)

    assert page =~ "Global Catalog"
    assert page =~ "Tea thread"
    assert page =~ "Meta thread"
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

  test "GET /ukko orders threads by recent sage activity and uses plain board labels", %{conn: conn} do
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
    reply = reply_fixture(board, thread, %{body: "reply body"})

    page =
      conn
      |> get("/ukko")
      |> html_response(200)

    assert page =~ ~s(form name="postcontrols" action="/post.php" method="post" hidden)

    assert page =~
             ~s(data-thread-watch data-board-uri="#{board.uri}" data-thread-id="#{PublicIds.public_id(thread)}")

    assert page =~ ~s(class="thread-top-controls")
    assert page =~ ~s(class="post-btn" title="Post menu" data-post-target="op_#{PublicIds.public_id(thread)}")
    assert page =~ ~s(class="post-btn" title="Post menu" data-post-target="reply_#{PublicIds.public_id(reply)}")
  end

  test "GET /ukko renders visible timestamps using the browser timezone cookie", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "ukkozone#{System.unique_integer([:positive])}", title: "Ukko Zone"})
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
    assert page_one =~ ~s(data-secure-href="/mod.php?/#{board.uri}/delete/#{PublicIds.public_id(first_thread)}/)
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
    assert page =~ "What is bnat?"
    assert page =~ "Recent reply"
    assert page =~ board.title
    assert page =~ ~s(class="boardlist")
    assert page =~ ~s(href="/recent.css)
  end

  test "GET / recent images include video posts with thumbnails", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "recentvid#{System.unique_integer([:positive])}", title: "Recent Video"})
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
    assert xml =~ "<loc>/#{board.uri}</loc>"
    assert xml =~ "<loc>/#{board.uri}/catalog.html</loc>"
    assert xml =~ "<loc>/#{board.uri}/res/#{PublicIds.public_id(thread)}.html</loc>"
  end

  test "GET /pages/flags renders the flags page", %{conn: conn} do
    author = moderator_fixture(%{username: "flagmaker"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "flags",
        title: "Flags",
        body: "Custom flags",
        mod_user_id: author.id
      })

    page =
      conn
      |> get("/pages/flags")
      |> html_response(200)

    assert page =~ "Pick custom flags for your posts"
    assert page =~ "/flags/compiled/"
    assert page =~ ~s(id="user_flag")
    assert page =~ "Apply"
  end

  test "GET /:board/flag redirects to the top-level flags page", %{conn: conn} do
    author = moderator_fixture(%{username: "flagboard"})
    board = board_fixture(%{uri: "bant", title: "International Random"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "flags",
        title: "Flags",
        body: "Custom flags",
        mod_user_id: author.id
      })

    conn =
      conn
      |> get("/#{board.uri}/flag")

    assert redirected_to(conn) == "/flags"
  end

  test "GET /flags renders the top-level flags page", %{conn: conn} do
    author = moderator_fixture(%{username: "flagglobal"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "flags",
        title: "Flags",
        body: "Custom flags",
        mod_user_id: author.id
      })

    page =
      conn
      |> get("/flags")
      |> html_response(200)

    assert page =~ "Pick custom flags for your posts"
    assert page =~ "/flags/compiled/"
    assert page =~ ~s(id="user_flag")
  end

  test "GET /flag redirects to /flags", %{conn: conn} do
    conn = get(conn, "/flag")
    assert redirected_to(conn) == "/flags"
  end

  test "GET /banners renders the banner picker page", %{conn: conn} do
    moderator_fixture()

    page =
      conn
      |> get("/banners")
      |> html_response(200)

    assert page =~ "<h1>Banners</h1>"
    assert page =~ ~s(src="/static/banners/)
    assert page =~ "Submit more at"
    refute page =~ ~s(id="exampleBox")
    refute page =~ ~s(data-flag-page)
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
    token = "token-1234567890123456"

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
    token = "watcher-token-unread"

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
    token = "watcher-fragment-token"

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
    _citing_reply = reply_fixture(board, thread, %{body: ">>#{PublicIds.public_id(owned_reply)} cited"})
    token = "watcher-you-fragment-token"

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
    token = "token-home-watch-123456"

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
    _citing_reply = reply_fixture(board, thread, %{body: ">>#{PublicIds.public_id(owned_reply)} cited"})
    token = "token-home-watch-you-123456"

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
