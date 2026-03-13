defmodule EirinchanWeb.SiteAssetsLayoutTest do
  use EirinchanWeb.ConnCase, async: false

  setup do
    previous =
      Application.get_env(:eirinchan, :site_assets, %{
        version: nil,
        custom_javascript: [],
        analytics_html: nil
      })

    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-site-assets-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :site_assets, previous)
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  test "root layout appends cache-busting versions and includes configured custom javascript", %{
    conn: conn
  } do
    Application.put_env(:eirinchan, :site_assets, %{
      version: "build-42",
      allow_custom_javascript: true,
      custom_javascript: "/js/custom-a.js, /js/custom-b.js\n/js/custom-c.js"
    })

    page =
      conn
      |> get("/search", %{"q" => ""})
      |> html_response(200)

    assert page =~ ~s(/stylesheets/style.css?v=build-42)
    assert page =~ ~s(/js/custom-a.js?v=build-42)
    assert page =~ ~s(/js/custom-b.js?v=build-42)
    assert page =~ ~s(/js/custom-c.js?v=build-42)
    refute page =~ ~s(/assets/app.js?v=build-42)
  end

  test "root layout sanitizes configured analytics html from instance config", %{conn: conn} do
    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        allow_analytics_html: true,
        analytics_html:
          ~s|<script id="analytics-hook">window.analyticsLoaded = true;</script><img id="analytics-pixel" src="/ok.png" onerror="alert(1)">|
      })

    page =
      conn
      |> get("/search", %{"q" => ""})
      |> html_response(200)

    refute page =~ ~s(<script id="analytics-hook">)
    refute page =~ "onerror="
    assert page =~ ~s(<img id="analytics-pixel" src="/ok.png")
  end

  test "root layout emits hardened browser security headers", %{conn: conn} do
    conn = get(conn, "/search", %{"q" => ""})
    [csp] = get_resp_header(conn, "content-security-policy")

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert get_resp_header(conn, "permissions-policy") != []
    assert get_resp_header(conn, "content-security-policy") != []
    refute csp =~ "script-src 'self' 'unsafe-inline'"
  end
end
