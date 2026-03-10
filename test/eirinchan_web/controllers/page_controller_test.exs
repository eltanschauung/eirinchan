defmodule EirinchanWeb.PageControllerTest do
  use EirinchanWeb.ConnCase

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

  test "GET /", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "tech", title: "Technology"})
    thread = thread_fixture(board, %{subject: "Opening", body: "Alpha bravo charlie delta"})
    reply_fixture(board, thread, %{body: "Recent reply body"})

    conn = get(conn, ~p"/")
    page = html_response(conn, 200)
    assert page =~ "Recent Posts"
    assert page =~ "Recent Images"
    assert page =~ "Latest Posts"
    assert page =~ "Stats"
    assert page =~ "Technology"
    assert page =~ "Recent reply body"
    assert page =~ ~s(href="/stylesheets/style.css)
    assert page =~ ~s(href="/recent.css)
    assert page =~ ~s(id="stylesheet" href="/stylesheets/yotsuba.css)
    assert page =~ ~s(data-stylesheet="yotsuba.css")
    assert page =~ ~s(var active_page = "index", board_name = null;)
    assert page =~ ~s(src="/main.js)
    assert page =~ "Tinyboard + vichan 5.2.2 +"
    assert page =~ ~s(href="https://github.com/username/eirinchan-v1")
  end

  test "GET / redirects to setup when no admin exists", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/setup"
  end

  test "GET /news renders public news entries", %{conn: conn} do
    author = moderator_fixture(%{username: "editor"})
    announce_author = moderator_fixture(%{username: "announcer"})
    page_author = moderator_fixture(%{username: "pageeditor"})

    {:ok, _announcement} =
      Eirinchan.Announcement.upsert(%{
        title: "System notice",
        body: "Read first",
        mod_user_id: announce_author.id
      })

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "faq",
        title: "FAQ",
        body: "Questions",
        mod_user_id: page_author.id
      })

    {:ok, _entry} =
      Eirinchan.News.create_entry(%{title: "Launch", body: "Board online", mod_user_id: author.id})

    conn = get(conn, ~p"/news")
    page = html_response(conn, 200)
    assert page =~ "News"
    assert page =~ "Launch"
    assert page =~ "Board online"
    assert page =~ "editor"
    assert page =~ "FAQ"
    assert page =~ ~s(class="boardlist")
    assert page =~ ~s(var active_page = "news", board_name = null;)
    assert page =~ "Tinyboard + vichan 5.2.2 +"
    assert page =~ ~s(href="https://github.com/username/eirinchan-v1")
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

  test "GET /faq serves stored full html overrides", %{conn: conn} do
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
    assert get_resp_header(faq_conn, "content-type") == ["text/html; charset=utf-8"]
  end

  test "GET /pages/faq uses the FAQ template when the page exists", %{conn: conn} do
    author = moderator_fixture(%{username: "faqwriter"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "faq",
        title: "FAQ",
        body: "Copied FAQ",
        mod_user_id: author.id
      })

    page =
      conn
      |> get("/pages/faq")
      |> html_response(200)

    assert page =~ "What is bnat?"
    assert page =~ "/faq/output_canvas.png"
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
    assert page =~ "Recent reply"
    assert page =~ board.title
    assert page =~ ~s(class="boardlist")
    assert page =~ ~s(href="/recent.css)
  end

  test "GET / renders recent theme body box from installed settings", %{conn: conn} do
    moderator_fixture()
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive])}", title: "Tea"})
    _thread = thread_fixture(board, %{subject: "Recent thread", body: "Opening"})

    {:ok, _theme} =
      Eirinchan.Themes.install_theme("recent", %{
        "title" => "Recent Posts",
        "exclude" => "",
        "limit_images" => "3",
        "limit_posts" => "30",
        "html" => "recent.html",
        "css" => "recent.css",
        "basecss" => "recent.css",
        "body_title" => "What is bnat?",
        "body" => "This is an international imageboard popula..."
      })

    page =
      conn
      |> get("/")
      |> html_response(200)

    assert page =~ ~s(class="box middle")
    assert page =~ "What is bnat?"
    assert page =~ "This is an international imageboard popula..."
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
    assert xml =~ "<loc>/#{board.uri}/res/#{thread.id}.html</loc>"
  end

  test "GET /pages/flag renders the flag page", %{conn: conn} do
    author = moderator_fixture(%{username: "flagmaker"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "flag",
        title: "Flag",
        body: "Custom flags",
        mod_user_id: author.id
      })

    page =
      conn
      |> get("/pages/flag")
      |> html_response(200)

    assert page =~ "Pick custom flags for your posts"
    assert page =~ "/flag/compiled/"
    assert page =~ ~s(id="user_flag")
    assert page =~ "Apply"
  end

  test "GET /:board/flag redirects to the top-level flag page", %{conn: conn} do
    author = moderator_fixture(%{username: "flagboard"})
    board = board_fixture(%{uri: "bant", title: "International Random"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "flag",
        title: "Flag",
        body: "Custom flags",
        mod_user_id: author.id
      })

    conn =
      conn
      |> get("/#{board.uri}/flag")

    assert redirected_to(conn) == "/flag"
  end

  test "GET /flag renders the top-level flag page", %{conn: conn} do
    author = moderator_fixture(%{username: "flagglobal"})

    {:ok, _page} =
      Eirinchan.CustomPages.create_page(%{
        slug: "flag",
        title: "Flag",
        body: "Custom flags",
        mod_user_id: author.id
      })

    page =
      conn
      |> get("/flag")
      |> html_response(200)

    assert page =~ "Pick custom flags for your posts"
    assert page =~ "/flag/compiled/"
    assert page =~ ~s(id="user_flag")
  end

  test "GET /flags redirects to /flag", %{conn: conn} do
    conn = get(conn, "/flags")
    assert redirected_to(conn) == "/flag"
  end
end
