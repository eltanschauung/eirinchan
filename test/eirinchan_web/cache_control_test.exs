defmodule EirinchanWeb.CacheControlTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.CacheControl

  test "unversioned JavaScript keeps the short compatibility cache" do
    assert CacheControl.cache_control_for_request("/js/main.js", "") ==
             "public, max-age=60"
  end

  test "versioned JavaScript and CSS are immutable" do
    assert CacheControl.cache_control_for_request("/js/main.js", "v=release-123") ==
             "public, max-age=31536000, immutable"

    assert CacheControl.cache_control_for_request("/stylesheets/site.css", "v=abc123") ==
             "public, max-age=31536000, immutable"
  end

  test "malformed and blank versions do not become immutable" do
    assert CacheControl.cache_control_for_request("/js/main.js", "v=") ==
             "public, max-age=60"

    assert CacheControl.cache_control_for_request("/js/main.js", "v=%") ==
             "public, max-age=60"
  end
end
