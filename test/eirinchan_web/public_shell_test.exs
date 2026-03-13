defmodule EirinchanWeb.PublicShellTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.PublicShell

  test "uses vichan default additional javascript by default" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/inline-expanding.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: false
    }

    assert PublicShell.javascript_urls(:thread, config) == [
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
             "/main.js",
             "/js/jquery.min.js",
             "/js/inline-expanding.js",
             "/js/jquery.mixitup.min.js",
             "/js/catalog.js"
           ]
  end

  test "compile mode suppresses separate additional javascript tags" do
    config = %{
      root: "/",
      url_javascript: "/main.js",
      additional_javascript: ["js/jquery.min.js", "js/inline-expanding.js"],
      additional_javascript_url: "/",
      additional_javascript_compile: true
    }

    assert PublicShell.javascript_urls(:thread, config) == ["/main.js"]
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
             "/main.js",
             "/js/jquery.min.js"
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
             "/main.js",
             "/js/jquery.min.js"
           ]
  end

  test "renders vichan styles block for style-select" do
    html =
      PublicShell.styles_html(
        [
          %{label: "Yotsuba", name: "default", stylesheet: "/stylesheets/yotsuba.css"},
          %{label: "Tomorrow", name: "tomorrow", stylesheet: "/stylesheets/tomorrow.css"}
        ],
        "Tomorrow"
      )

    assert html =~ ~s(<div class="styles">)
    assert html =~ ~s([Yotsuba])
    assert html =~ ~s([Tomorrow])
    assert html =~ ~s(class="selected")
    assert html =~ "onclick=\"return changeStyle(&quot;Yotsuba&quot;, this)\""
    assert html =~ "onclick=\"return changeStyle(&quot;Tomorrow&quot;, this)\""
  end

  test "renders password generation variables into head html" do
    html = PublicShell.head_html("index")

    assert html =~ "genpassword_chars"
    assert html =~ "post_success_cookie_name"
    assert html =~ "eirinchan_posted"
  end

  test "renders a hidden style select for the options menu" do
    html =
      PublicShell.style_select_html(
        [
          %{label: "Yotsuba", name: "default", stylesheet: "/stylesheets/yotsuba.css"},
          %{label: "Tomorrow", name: "tomorrow", stylesheet: "/stylesheets/tomorrow.css"}
        ],
        "Tomorrow"
      )

    assert html =~ ~s(<div id="style-select")
    assert html =~ ~s(display:none)
    assert html =~ ~s(Style: <select)
    assert html =~ ~s(<option value="Yotsuba">Yotsuba</option>)
    assert html =~ ~s(<option value="Tomorrow" selected="selected">Tomorrow</option>)
    assert html =~ ~s|onchange="return changeStyle(this.value)"|
  end
end
