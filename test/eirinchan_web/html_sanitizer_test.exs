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
end
