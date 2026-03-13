defmodule EirinchanWeb.HtmlSanitizerTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.HtmlSanitizer

  test "removes script tags inline handlers and javascript urls" do
    html =
      ~s|<div onclick="alert(1)"><script>alert(1)</script><a href="javascript:alert(1)">x</a><img src="ok.png" onerror="alert(1)"></div>|

    sanitized = HtmlSanitizer.sanitize_fragment(html)

    refute sanitized =~ "<script"
    refute sanitized =~ "onclick="
    refute sanitized =~ "onerror="
    refute sanitized =~ "javascript:"
    assert sanitized =~ ~s(href="#")
    assert sanitized =~ ~s(src="ok.png")
  end

  test "removes style and link tags and dangerous style attributes" do
    html =
      ~s|<style>@import url(http://evil)</style><link rel="stylesheet" href="http://evil"><div style="width:1px;expression(alert(1))">x</div><p style="color:red">ok</p>|

    sanitized = HtmlSanitizer.sanitize_fragment(html)

    refute sanitized =~ "<style"
    refute sanitized =~ "<link"
    refute sanitized =~ "expression("
    assert sanitized =~ ~s(<p style="color:red">ok</p>)
  end

  test "neutralizes data urls and strips srcset" do
    html =
      ~s|<a href="data:text/html;base64,AAAA">x</a><img src="data:image/svg+xml;base64,AAAA" srcset="/a.png 1x, /b.png 2x">|

    sanitized = HtmlSanitizer.sanitize_fragment(html)

    assert sanitized =~ ~s(href="#")
    assert sanitized =~ ~s(src="#")
    refute sanitized =~ "srcset="
  end
end
