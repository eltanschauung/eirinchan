defmodule Eirinchan.LegacyPageBodyTest do
  use ExUnit.Case, async: true

  alias Eirinchan.LegacyPageBody

  test "preserves fragments and replaces blank input with the default" do
    assert LegacyPageBody.normalize("  <p>Content</p>  ", fn -> "default" end) ==
             "<p>Content</p>"

    assert LegacyPageBody.normalize("  ", fn -> "default" end) == "default"
    assert LegacyPageBody.normalize(nil, fn -> "default" end) == nil
  end

  test "extracts a configured fragment from a legacy document" do
    html = """
    <!doctype html><html><body>
    <div class="box-wrap faq-page-shell"><p>FAQ</p></div>
    <footer>Footer</footer>
    </body></html>
    """

    assert LegacyPageBody.normalize(html, fn -> "default" end,
             content_regex: ~r|(<div class="box-wrap faq-page-shell">.*?</div>\s*)<footer|s
           ) == "<div class=\"box-wrap faq-page-shell\"><p>FAQ</p></div>"
  end

  test "removes shared and page-specific shell wrappers from a legacy body" do
    html = """
    <html><body>
    <div class="boardlist">Boards</div><a id="top"></a>
    <header>Header</header><style>.old {}</style><p>Content</p>
    <script>unsafe()</script><footer>Footer</footer><hr>
    </body></html>
    """

    assert LegacyPageBody.normalize(html, fn -> "default" end,
             strip: [:header, :style, :horizontal_rule]
           ) == "<p>Content</p>"
  end
end
