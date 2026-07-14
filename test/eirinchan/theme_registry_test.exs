defmodule Eirinchan.ThemeRegistryTest do
  use ExUnit.Case, async: true

  alias Eirinchan.ThemeRegistry

  test "contains only implemented template themes" do
    names = ThemeRegistry.all() |> Enum.map(& &1.name) |> MapSet.new()

    assert names == MapSet.new(~w(feedback recent rss sitemap ukko))

    refute MapSet.member?(names, "catalog")
    refute MapSet.member?(names, "IpAccessAuth")
    refute MapSet.member?(names, "faq")
    refute MapSet.member?(names, "categories")
    refute MapSet.member?(names, "frameset")
    refute MapSet.member?(names, "index")
  end

  test "protects reserved routes" do
    assert ThemeRegistry.safe_route_segment?("okuu")
    refute ThemeRegistry.safe_route_segment?("manage")
    refute ThemeRegistry.safe_route_segment?("../manage")
  end
end
