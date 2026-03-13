defmodule Eirinchan.NewsBlotterTest do
  use ExUnit.Case, async: true

  alias Eirinchan.NewsBlotter

  test "sanitizes blotter entry messages before rendering" do
    html =
      NewsBlotter.render_html(%{
        news_blotter_entries: [
          %{
            date: "03/13/26",
            message:
              ~s|<a href="javascript:alert(1)" onclick="alert(1)">bad</a><span class="glow">ok</span><script>alert(1)</script>|
          }
        ]
      })

    refute html =~ "<script"
    refute html =~ "onclick="
    refute html =~ "javascript:"
    assert html =~ ~s(href="#")
    assert html =~ ~s(<span class="glow">ok</span>)
  end
end
