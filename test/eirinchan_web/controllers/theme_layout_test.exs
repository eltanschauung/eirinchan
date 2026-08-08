defmodule EirinchanWeb.ThemeLayoutTest do
  use EirinchanWeb.ConnCase, async: false

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-theme-layout-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)
    :ok = Eirinchan.Settings.persist_instance_config(%{})

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  test "selected theme stylesheet is rendered into the root layout", %{conn: conn} do
    page =
      conn
      |> put_req_cookie("theme", "tomorrow")
      |> get("/search.php", %{"q" => ""})
      |> html_response(200)

    refute page =~ ~s(action="/theme")
    assert page =~ ~s(/stylesheets/style.css)
    assert page =~ "Tomorrow"
    assert page =~ "Blue Archive"
    assert page =~ "Spooky Suwako"
    assert page =~ "Nazrin Grey"
    assert page =~ "Reimu Red"
    assert page =~ "Marisa Black"
    assert page =~ "Christmas"
    assert page =~ "Eientei1"
    assert page =~ "Yotsuba B"
    assert page =~ "Yotsuba"
    assert page =~ "/stylesheets/tomorrow.css"
    assert page =~ "/stylesheets/bluearchive.css"
    assert page =~ "/stylesheets/spooky_suwako.css"
    assert page =~ "/stylesheets/nazrin_grey.css"
    assert page =~ "/stylesheets/reimu_red.css"
    assert page =~ "/stylesheets/marisa_black.css"
    assert page =~ "/stylesheets/christmas.css"
    assert page =~ "/stylesheets/eientei1.css"
    assert page =~ "/stylesheets/yotsuba.css"
    refute page =~ "Keyed Frog"

    labels =
      Regex.scan(~r/<option[^>]*>([^<]+)<\/option>/, page, capture: :all_but_first)
      |> List.flatten()

    blue_archive_index = Enum.find_index(labels, &(&1 == "Blue Archive"))

    assert Enum.slice(labels, blue_archive_index + 1, 4) == [
             "Spooky Suwako",
             "Nazrin Grey",
             "Reimu Red",
             "Marisa Black"
           ]
  end

  test "instance default dark theme is selected without a saved theme", %{conn: conn} do
    :ok = Eirinchan.Settings.persist_instance_config(%{default_theme_dark: "tomorrow"})

    page =
      conn
      |> put_req_cookie("eirinchan_color_scheme", "dark")
      |> get("/search.php", %{"q" => ""})
      |> html_response(200)

    assert page =~ ~s(id="stylesheet")
    assert page =~ ~s(href="/stylesheets/tomorrow.css)
  end
end
