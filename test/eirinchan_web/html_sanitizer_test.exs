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
    refute sanitized =~ "expression("
    assert sanitized =~ ~s(<div>x</div>)
    assert sanitized =~ ~s(<p style="color:red">ok</p>)
  end

  test "preserves only valid YouTube player data attributes" do
    html =
      ~s|<div class="video-container" data-video="dQw4w9WgXcQ"><img width="208" height="156" decoding="async"></div>| <>
        ~s|<div data-video="bad id" onclick="alert(1)">unsafe</div>|

    sanitized = HtmlSanitizer.sanitize_fragment(html)

    assert sanitized =~ ~s(data-video="dQw4w9WgXcQ")
    assert sanitized =~ ~s(width="208")
    assert sanitized =~ ~s(height="156")
    assert sanitized =~ ~s(decoding="async")
    refute sanitized =~ "bad id"
    refute sanitized =~ "onclick"
  end

  test "neutralizes data urls and strips srcset" do
    html =
      ~s|<a href="data:text/html;base64,AAAA">x</a><img src="data:image/svg+xml;base64,AAAA" srcset="/a.png 1x, /b.png 2x">|

    sanitized = HtmlSanitizer.sanitize_fragment(html)

    assert sanitized =~ ~s(href="#")
    assert sanitized =~ ~s(src="#")
    refute sanitized =~ "srcset="
  end

  test "blocks unquoted and entity-obfuscated script urls" do
    html = ~s|<a href=javascript:alert(1)>one</a><a href="jav&#x61;script:alert(2)">two</a>|

    sanitized = HtmlSanitizer.sanitize_fragment(html)

    refute sanitized =~ "javascript:"
    assert sanitized =~ ~s|<a href="#">one</a>|
    assert sanitized =~ ~s|<a href="#">two</a>|
  end

  test "drops executable namespaces forms and their contents" do
    html = ~s|<svg><a href="https://evil.test">svg</a></svg><form><input name="x"></form><math><mtext>x</mtext></math>safe|

    assert HtmlSanitizer.sanitize_fragment(html) == "safe"
  end

  test "preserves common rich text and secures blank-target links" do
    html = ~s|<h2 class="title">Heading</h2><table><tr><th scope="col">A</th></tr></table><a href="https://example.test" target="_blank">link</a>|

    sanitized = HtmlSanitizer.sanitize_fragment(html)

    assert sanitized =~ ~s|<h2 class="title">Heading</h2>|
    assert sanitized =~ ~s|<th scope="col">A</th>|
    assert sanitized =~ ~s|target="_blank"|
    assert sanitized =~ ~s|rel="noopener noreferrer"|
  end

  test "preserves the FAQ's inert legacy tags and narrowly scoped layout styles" do
    html = """
    <div style="margin-bottom:40px;position:fixed">
      <p1>copy <px>blue</px> <py>green</py></p1>
      <hr style="margin:6px;opacity:0;position:absolute">
      <img src="/faq/example.png" style="max-width:285px;height:auto;text-align:center;margin:0;position:fixed">
    </div>
    """

    sanitized = HtmlSanitizer.sanitize_fragment(html)

    assert sanitized =~ ~s|<div style="margin-bottom:40px">|
    assert sanitized =~ "<p1>"
    assert sanitized =~ ~s|<px>blue</px>|
    assert sanitized =~ ~s|<py>green</py>|
    assert sanitized =~ ~s|<hr style="margin:6px;opacity:0"|

    assert sanitized =~
             ~s|<img src="/faq/example.png" style="max-width:285px;height:auto;text-align:center;margin:0"|

    refute sanitized =~ "position:"
  end
end
