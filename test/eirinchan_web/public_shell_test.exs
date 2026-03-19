defmodule EirinchanWeb.PublicShellTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.{PostComponents, PublicShell}

  test "uses vichan default additional javascript by default" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/inline-expanding.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js",
             "/js/inline-expanding.js"
           ]
  end

  test "catalog appends required theme scripts" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/inline-expanding.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:catalog, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js",
             "/js/inline-expanding.js",
             "/js/catalog.js",
             "/js/catalog-search.js"
           ]
  end

  test "catalog filters thread-only scripts from the public shell" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: [
        "js/jquery.min.js",
        "js/thread-stats.js",
        "js/quick-reply.js",
        "js/auto-reload.js",
        "js/catalog-search.js"
      ],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:catalog, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js",
             "/js/auto-reload.js",
             "/js/catalog-search.js",
             "/js/catalog.js"
           ]
  end

  test "compile mode emits page bundles instead of separate local script tags" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/inline-expanding.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: true
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/bundle-public-core.js",
             "/js/bundle-public-thread.js"
           ]
  end

  test "compile mode keeps remote scripts outside bundles" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "https://cdn.example.test/remote.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: true,
      allow_remote_script_urls: true
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/bundle-public-core.js",
             "/js/bundle-public-thread.js",
             "https://cdn.example.test/remote.js"
           ]
  end

  test "compile mode uses the catalog bundle for catalog pages" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/catalog-search.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: true
    }

    assert PublicShell.javascript_urls(:catalog, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/bundle-public-core.js",
           "/js/bundle-public-catalog.js"
           ]
  end

  test "compile mode normalizes string page names to the correct bundle" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/catalog-search.js", "js/auto-reload.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: true
    }

    assert PublicShell.javascript_urls("ukko", config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/bundle-public-core.js",
             "/js/bundle-public-index.js",
             "/js/bundle-public-ukko.js"
           ]
  end

  test "filters dangerous additional javascript entries" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "javascript:alert(1)", "../evil.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js"
           ]
  end

  test "filters remote and user-code javascript unless explicitly enabled" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: [
        "js/jquery.min.js",
        "https://cdn.example.test/remote.js",
        "js/options/user-js.js",
        "js/options/user-css.js"
      ],
      additional_javascript_url: "/",
      additional_javascript_compile: false,
      allow_remote_script_urls: false,
      allow_user_custom_code: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js"
           ]
  end

  test "allows remote and user-code javascript when explicitly enabled" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: [
        "js/jquery.min.js",
        "https://cdn.example.test/remote.js",
        "js/options/user-js.js"
      ],
      additional_javascript_url: "/",
      additional_javascript_compile: false,
      allow_remote_script_urls: true,
      allow_user_custom_code: true
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js",
             "https://cdn.example.test/remote.js",
             "/js/options/user-js.js"
           ]
  end

  test "deduplicates repeated additional javascript entries" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: [
        "js/jquery.min.js",
        "js/jquery.min.js",
        "js/inline-expanding.js"
      ],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js",
             "/js/inline-expanding.js"
           ]
  end

  test "injects post-menu before dependent menu scripts" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/post-filter.js", "js/fix-report-delete-submit.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js",
             "/js/hide-threads.js",
             "/js/post-menu.js",
             "/js/post-filter.js",
             "/js/fix-report-delete-submit.js"
           ]
  end

  test "filters legacy unspoiler script from additional javascript" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/unspoiler3.js", "js/ajax.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js",
           "/js/ajax.js"
           ]
  end

  test "filters legacy style select script from additional javascript" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/style-select.js", "js/options/general.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js",
             "/js/options/general.js"
           ]
  end

  test "filters redundant legacy scripts now handled lower in the stack" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: [
        "js/jquery.min.js",
        "js/show-op.js",
        "js/show-backlinks.js",
        "js/show-own-posts.js",
        "js/catalog-link.js",
        "js/download-original.js",
        "js/thread-stats.js"
      ],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js",
             "/js/thread-stats.js"
           ]
  end

  test "falls back to root for dangerous additional javascript base urls" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js"],
      additional_javascript_url: "javascript:alert(1)",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
             "/js/runtime-config.js",
             "/main.js",
             "/js/jquery.min.js"
           ]
  end

  test "renders vichan styles block for style-select" do
    html =
      PostComponents.styles_block(%{
        theme_options: [
          %{label: "Yotsuba", name: "default", stylesheet: "/stylesheets/yotsuba.css"},
          %{label: "Tomorrow", name: "tomorrow", stylesheet: "/stylesheets/tomorrow.css"}
        ],
        theme_label: "Tomorrow"
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ ~s(<div class="styles">)
    assert html =~ ~s([Yotsuba])
    assert html =~ ~s([Tomorrow])
    assert html =~ ~s(class="selected")
    assert html =~ ~s(data-style-name="Yotsuba")
    assert html =~ ~s(data-style-name="Tomorrow")
  end

  test "renders runtime configuration metadata into structured head assigns" do
    head_meta = PublicShell.head_meta("index")

    assert head_meta["eirinchan:active-page"] == "index"
    assert Map.has_key?(head_meta, "eirinchan:genpassword-chars")
    assert head_meta["eirinchan:post-success-cookie-name"] == "eirinchan_posted"
  end
end
