defmodule EirinchanWeb.ThemeManagementControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.Settings
  alias Eirinchan.Themes

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(System.tmp_dir!(), "eirinchan-themes-#{System.unique_integer([:positive])}.json")

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)
    Settings.refresh_instance_config_cache()

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      Settings.refresh_instance_config_cache()
      File.rm(path)
    end)

    :ok
  end

  test "theme manager lists implemented landing themes but not core features", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    themes_page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/themes/browser")
      |> html_response(200)

    assert themes_page =~ "Manage Themes"
    assert themes_page =~ "RSS"
    assert themes_page =~ "Sitemap"
    assert themes_page =~ "Statistics"
    assert themes_page =~ "Overboard (Ukko)"
    refute themes_page =~ ">FAQ<"
    refute themes_page =~ "Categories"
    refute themes_page =~ "Frameset"
    refute themes_page =~ ">Index<"
    refute themes_page =~ "IP Access Authentication"
    refute themes_page =~ ">Catalog<"

    missing_catalog =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/themes/browser/catalog")

    assert html_response(missing_catalog, 404) =~ "Theme not found"
  end

  test "statistics is disabled by default and renders every chart after installation", %{
    conn: conn
  } do
    moderator = moderator_fixture(%{role: "admin"})

    refute Themes.page_theme_enabled?("stats")
    assert conn |> get("/stats") |> html_response(404) =~ "Error 404"

    install_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> post("/manage/themes/browser/stats", %{
        "title" => "Whale Statistics"
      })

    assert redirected_to(install_conn) == "/manage/themes/browser/stats"
    assert Themes.page_theme_enabled?("stats")

    page = conn |> recycle() |> get("/stats") |> html_response(200)
    document = Floki.parse_document!(page)

    assert page =~ "Whale Statistics"
    assert page =~ ~s(href="/stats.css)
    assert conn |> recycle() |> get("/stats.css") |> response(200) =~ ".statistics-chart"
    today = :calendar.local_time() |> elem(0) |> Date.from_erl!()

    assert length(Floki.find(document, ".statistics-chart")) == 8

    assert length(Floki.find(document, "#posts-per-month-#{today.year} .statistics-chart-column")) ==
             12

    assert length(Floki.find(document, ~s([id^="pph-"] .statistics-chart-column))) == 48

    assert length(
             Floki.find(
               document,
               "#average-visitors-per-hour-last-week .statistics-chart-column"
             )
           ) == 24

    assert length(
             Floki.find(
               document,
               "#average-posts-per-hour-last-week .statistics-chart-column"
             )
           ) == 24

    assert Floki.attribute(document, ".statistics-chart", "id") |> Enum.take(-2) == [
             "average-visitors-per-hour-last-week",
             "average-posts-per-hour-last-week"
           ]

    assert length(Floki.find(document, "#visitors-current-month .statistics-chart-column")) ==
             Date.days_in_month(today)
  end

  test "recent reconfigure owns the editable homepage HTML", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    theme_page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/themes/browser/recent")
      |> html_response(200)

    assert theme_page =~ "Configuring theme: RecentPosts"
    assert theme_page =~ "Homepage HTML"
    assert theme_page =~ "{{public_boards}}"
    assert theme_page =~ "where the live Public Boards table should appear"
    assert theme_page =~ ~s(name="body")
    assert theme_page =~ ~s(rows="30")

    document = Floki.parse_document!(theme_page)

    assert document
           |> Floki.find("form .field > label")
           |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
           |> Enum.take(-3) ==
             ["Recent images", "Recent posts", "Use Board Subtitle for Latest Posts"]

    assert document
           |> Floki.find(~s(input[type="hidden"][name="use_board_subtitle"][value="false"]))
           |> length() == 1

    assert document
           |> Floki.find("#theme-recent-use_board_subtitle")
           |> Floki.attribute("checked") != []

    refute theme_page =~ ~s(name="body_title")
    refute theme_page =~ "HTML file"
    refute theme_page =~ "CSS file"
  end

  test "recent reconfigure persists an unchecked Latest Posts subtitle option", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    response =
      conn
      |> login_moderator(moderator)
      |> post("/manage/themes/browser/recent", %{
        "title" => "Recent Posts",
        "body" => "<div class=\"box middle\">Managed home</div>",
        "exclude" => "",
        "limit_images" => "3",
        "limit_posts" => "30",
        "use_board_subtitle" => "false"
      })

    assert redirected_to(response) == "/manage/themes/browser/recent"
    refute Themes.theme_settings("recent")["use_board_subtitle"]
  end

  test "legacy Recent settings migrate the managed home page instead of the placeholder body" do
    moderator = moderator_fixture(%{role: "admin"})
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Eirinchan.Repo.insert_all(Eirinchan.CustomPages.Page, [
      %{
        slug: "home",
        title: "Managed Home",
        body: "<div class=\"box middle\">Preserve this enhanced homepage</div>",
        mod_user_id: moderator.id,
        inserted_at: now,
        updated_at: now
      }
    ])

    assert :ok =
             Settings.persist_instance_config(%{
               template_themes: %{
                 installed: %{
                   "IpAccessAuth" => %{"path" => "auth", "title" => "Gate"},
                   "catalog" => %{"title" => "Catalog"},
                   "recent" => %{
                     "title" => "Recent Posts",
                     "body" => "Welcome to whale town",
                     "body_title" => "Whale whale",
                     "html" => "recent.html",
                     "css" => "recent.css",
                     "basecss" => "recent.css",
                     "limit_images" => "3",
                     "limit_posts" => "30"
                   }
                 }
               }
             })

    settings = Themes.theme_settings("recent")
    assert settings["title"] == "Managed Home"
    assert settings["body"] =~ "Preserve this enhanced homepage"
    refute settings["body"] =~ "Welcome to whale town"

    assert {:ok, _theme} = Themes.install_theme("recent", settings)
    refute Eirinchan.CustomPages.get_page_by_slug("home")

    installed =
      Application.fetch_env!(:eirinchan, :instance_config_path)
      |> File.read!()
      |> Jason.decode!()
      |> get_in(["template_themes", "installed"])

    persisted = installed["recent"]

    assert persisted["title"] == "Managed Home"
    assert persisted["body"] =~ "Preserve this enhanced homepage"
    refute Map.has_key?(persisted, "body_title")
    refute Map.has_key?(persisted, "html")
    refute Map.has_key?(persisted, "css")
    refute Map.has_key?(persisted, "basecss")
    refute Map.has_key?(installed, "catalog")
    refute Map.has_key?(installed, "IpAccessAuth")
  end

  test "catalog is always available and is not installable", %{conn: conn} do
    board = board_fixture(%{uri: "meta#{System.unique_integer([:positive])}", title: "Meta"})
    thread_fixture(board, %{subject: "Catalog thread", body: "Body"})

    assert Themes.page_theme_enabled?("catalog")
    assert :ok = Themes.enable_page_theme("catalog")
    assert {:error, :always_enabled} = Themes.disable_page_theme("catalog")

    assert conn
           |> get("/#{board.uri}/catalog.html")
           |> html_response(200) =~ "Catalog thread"
  end

  test "retired landing themes are unavailable", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    for name <- ~w(categories frameset index) do
      refute Themes.page_theme_enabled?(name)

      response =
        conn
        |> recycle()
        |> login_moderator(moderator)
        |> get("/manage/themes/browser/#{name}")

      assert html_response(response, 404) =~ "Theme not found"

      assert conn
             |> recycle()
             |> get("/#{name}")
             |> html_response(404)
    end

    assert Themes.page_theme_enabled?("recent")
    assert conn |> recycle() |> get("/") |> html_response(200) =~ "Recent Images"
  end

  test "RSS renders escaped recent-post data at its fixed route", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{uri: "rss#{System.unique_integer([:positive])}", title: "RSS & News"})
    thread_fixture(board, %{body: "A <tag> & text"})

    install_conn =
      conn
      |> login_moderator(moderator)
      |> post("/manage/themes/browser/rss", %{"title" => "Feed & Updates", "limit_posts" => "10"})

    assert redirected_to(install_conn) == "/manage/themes/browser/rss"

    response = conn |> recycle() |> get("/recent.xml")
    body = response.resp_body

    assert response.status == 200
    assert get_resp_header(response, "content-type") |> hd() =~ "application/rss+xml"
    assert body =~ "<rss version=\"2.0\">"
    assert body =~ "Feed &amp; Updates"
    assert body =~ "RSS &amp; News"
    refute body =~ "<tag>"
  end

  test "theme settings reject unsafe routes", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    invalid_ukko =
      conn
      |> login_moderator(moderator)
      |> post("/manage/themes/browser/ukko", %{"uri" => "manage"})

    assert html_response(invalid_ukko, 422) =~ "conflicts with a built-in route"
  end

  test "faq is managed only as a global static page", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    assert {:ok, faq_page} =
             Eirinchan.CustomPages.create_page(%{
               slug: "faq",
               title: "FAQ",
               body: "Static FAQ body",
               mod_user_id: moderator.id
             })

    missing_theme =
      conn
      |> login_moderator(moderator)
      |> get("/manage/themes/browser/faq")

    assert html_response(missing_theme, 404) =~ "Theme not found"

    static_pages =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/pages/browser")
      |> html_response(200)

    assert static_pages =~ "Static FAQ body"
    assert static_pages =~ ~s(href="/faq")
    assert conn |> recycle() |> get("/faq") |> html_response(200) =~ "Static FAQ body"
    assert Eirinchan.CustomPages.get_page_by_slug("faq").id == faq_page.id
  end
end
