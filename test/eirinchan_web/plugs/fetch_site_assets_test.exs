defmodule EirinchanWeb.Plugs.FetchSiteAssetsTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.Plugs.FetchSiteAssets

  test "parse_custom_javascript accepts comma and newline separated values" do
    assert FetchSiteAssets.parse_custom_javascript("/js/one.js, /js/two.js\n/js/three.js") == [
             "/js/one.js",
             "/js/two.js",
             "/js/three.js"
           ]
  end

  test "parse_custom_javascript flattens lists and removes duplicates" do
    assert FetchSiteAssets.parse_custom_javascript([
             "/js/one.js, /js/two.js",
             ["/js/two.js", "/js/three.js"]
           ]) == ["/js/one.js", "/js/two.js", "/js/three.js"]
  end

  test "parse_custom_javascript rejects dangerous urls" do
    assert FetchSiteAssets.parse_custom_javascript(
             "/js/one.js, javascript:alert(1), data:text/javascript,../evil.js"
           ) == ["/js/one.js"]
  end

  test "parse_custom_javascript rejects remote urls by default" do
    assert FetchSiteAssets.parse_custom_javascript(
             "/js/one.js, https://evil.test/payload.js, //cdn.example.test/x.js"
           ) == ["/js/one.js"]
  end

  test "parse_custom_javascript allows remote urls when explicitly enabled" do
    assert FetchSiteAssets.parse_custom_javascript(
             "/js/one.js, https://cdn.example.test/payload.js",
             allow_remote_script_urls: true
           ) == ["/js/one.js", "https://cdn.example.test/payload.js"]
  end
end
