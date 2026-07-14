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
    assert themes_page =~ "Overboard (Ukko)"
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

  test "recent reconfigure owns the editable homepage HTML", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    theme_page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/themes/browser/recent")
      |> html_response(200)

    assert theme_page =~ "Configuring theme: RecentPosts"
    assert theme_page =~ "Homepage HTML"
    assert theme_page =~ ~s(name="body")
    assert theme_page =~ ~s(rows="30")
    refute theme_page =~ ~s(name="body_title")
    refute theme_page =~ "HTML file"
    refute theme_page =~ "CSS file"
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

  test "admin can install and uninstall faq theme", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    refute Eirinchan.CustomPages.get_page_by_slug("faq")

    install_conn =
      conn
      |> login_moderator(moderator)
      |> post("/manage/themes/browser/faq", %{})

    assert redirected_to(install_conn) == "/manage/themes/browser/faq"
    assert faq_page = Eirinchan.CustomPages.get_page_by_slug("faq")
    refute faq_page.body =~ "<!doctype html>"
    assert faq_page.body =~ "What is bnat?"

    assert conn |> recycle() |> get("/faq") |> html_response(200) =~ "What is bnat?"

    uninstall_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> delete("/manage/themes/browser/faq")

    assert redirected_to(uninstall_conn) == "/manage/themes/browser"
    refute Eirinchan.CustomPages.get_page_by_slug("faq")
  end

  test "faq reconfigure page edits sanitized FAQ source", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    save_conn =
      conn
      |> login_moderator(moderator)
      |> post("/manage/themes/browser/faq", %{
        "html" => "<!doctype html><html><body><h1>Theme FAQ</h1></body></html>"
      })

    assert redirected_to(save_conn) == "/manage/themes/browser/faq"
    refute Eirinchan.CustomPages.get_page_by_slug("faq").body =~ "<!doctype html>"
    assert Eirinchan.CustomPages.get_page_by_slug("faq").body =~ "Theme FAQ"
  end
end
