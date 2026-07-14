defmodule Eirinchan.ThemeRegistryTest do
  use ExUnit.Case, async: true

  alias Eirinchan.ThemeRegistry

  test "contains only implemented template themes" do
    names = ThemeRegistry.all() |> Enum.map(& &1.name) |> MapSet.new()

    assert names ==
             MapSet.new(~w(categories faq feedback frameset index recent rss sitemap ukko))

    refute MapSet.member?(names, "catalog")
    refute MapSet.member?(names, "IpAccessAuth")
  end

  test "canonicalizes allowlisted YouTube URLs and rejects other iframe hosts" do
    assert ThemeRegistry.youtube_embed_url("https://youtu.be/dQw4w9WgXcQ") ==
             "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"

    assert ThemeRegistry.youtube_embed_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ") ==
             "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"

    refute ThemeRegistry.youtube_embed_url("https://example.com/embed/dQw4w9WgXcQ")
  end

  test "protects reserved routes and unsafe media schemes" do
    assert ThemeRegistry.safe_route_segment?("okuu")
    refute ThemeRegistry.safe_route_segment?("manage")
    refute ThemeRegistry.safe_route_segment?("../manage")

    assert ThemeRegistry.media_url("/site_logo.png") == "/site_logo.png"

    assert ThemeRegistry.media_url("https://cdn.example/logo.png") ==
             "https://cdn.example/logo.png"

    assert ThemeRegistry.media_url("javascript:alert(1)") == ""
    assert ThemeRegistry.media_url("//evil.example/logo.png") == ""
    assert ThemeRegistry.media_url("https://user:pass@evil.example/logo.png") == ""
  end
end
