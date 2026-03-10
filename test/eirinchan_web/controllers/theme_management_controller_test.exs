defmodule EirinchanWeb.ThemeManagementControllerTest do
  use EirinchanWeb.ConnCase, async: false

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(System.tmp_dir!(), "eirinchan-themes-#{System.unique_integer([:positive])}.json")

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  test "admin can browse available vichan themes and open a theme config page", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    themes_page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/themes/browser")
      |> html_response(200)

    assert themes_page =~ "Manage Themes"
    assert themes_page =~ "Catalog"
    assert themes_page =~ "FAQ"
    assert themes_page =~ "Overboard (Ukko)"
    assert themes_page =~ "Install"

    theme_page =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> get("/manage/themes/browser/catalog")
      |> html_response(200)

    assert theme_page =~ "Configuring theme: Catalog"
    assert theme_page =~ "Included boards"
    assert theme_page =~ "Use tooltipster"
  end

  test "recent theme exposes body fields on its config page", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})

    theme_page =
      conn
      |> login_moderator(moderator)
      |> get("/manage/themes/browser/recent")
      |> html_response(200)

    assert theme_page =~ "Configuring theme: RecentPosts"
    assert theme_page =~ "Body Title"
    assert theme_page =~ "Body"
    assert theme_page =~ ~s(name="body_title")
    assert theme_page =~ ~s(name="body")
    assert theme_page =~ "<textarea"
  end

  test "admin can install, rebuild, and uninstall catalog from the themes page", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture(%{uri: "meta#{System.unique_integer([:positive])}", title: "Meta"})
    thread_fixture(board, %{subject: "Catalog thread", body: "Body"})

    legacy_conn =
      conn
      |> login_moderator(moderator)
      |> get("/mod.php?/themes")

    assert redirected_to(legacy_conn) == "/manage/themes/browser"

    disabled_conn =
      conn
      |> recycle()
      |> get("/#{board.uri}/catalog.html")

    assert response(disabled_conn, 404)

    install_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> post("/manage/themes/browser/catalog", %{
        "title" => "Catalog",
        "boards" => "*",
        "update_on_posts" => "on",
        "use_tooltipster" => "on"
      })

    assert redirected_to(install_conn) == "/manage/themes/browser/catalog"
    assert Eirinchan.Themes.page_theme_enabled?("catalog")

    rebuilt_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> post("/manage/themes/browser/catalog/rebuild")

    assert redirected_to(rebuilt_conn) == "/manage/themes/browser/catalog"

    catalog_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/catalog.html")
      |> html_response(200)

    assert catalog_page =~ "Catalog thread"

    uninstall_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> delete("/manage/themes/browser/catalog")

    assert redirected_to(uninstall_conn) == "/manage/themes/browser"
    refute Eirinchan.Themes.page_theme_enabled?("catalog")

    missing_catalog_conn =
      conn
      |> recycle()
      |> get("/#{board.uri}/catalog.html")

    assert response(missing_catalog_conn, 404)
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
    assert faq_page.body =~ "<!doctype html>"
    assert faq_page.body =~ "What is bnat?"

    faq_page_response =
      conn
      |> recycle()
      |> get("/faq")
      |> html_response(200)

    assert faq_page_response =~ "What is bnat?"

    uninstall_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> delete("/manage/themes/browser/faq")

    assert redirected_to(uninstall_conn) == "/manage/themes/browser"
    refute Eirinchan.CustomPages.get_page_by_slug("faq")
  end
end
