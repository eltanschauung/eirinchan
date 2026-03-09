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
end
