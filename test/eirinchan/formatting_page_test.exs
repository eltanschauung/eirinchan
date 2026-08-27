defmodule Eirinchan.FormattingPageTest do
  use ExUnit.Case, async: true

  alias Eirinchan.FormattingPage

  test "puts the gem sticker first in the left formatting column" do
    html =
      FormattingPage.default_body([
        %{token: "concern2", path: "/whalestickers/concern2.png", width: 120, height: 120},
        %{token: "gem", path: "/whalestickers/gem.png", width: 388, height: 228}
      ])

    {:ok, document} = Floki.parse_fragment(html)

    assert [first_sticker | _] =
             Floki.find(document, ".formatting-sticker-column:first-child img")

    assert Floki.attribute(first_sticker, "src") == ["/whalestickers/gem.png"]
  end

  test "upgrades stored sticker markup without altering unrelated images" do
    html = """
    <div>
      <img src="/whalestickers/gojo.png" title="gojo">
      <img src="https://example.com/unrelated.png" title="unrelated">
    </div>
    """

    normalized =
      FormattingPage.normalize_body(html, [
        %{token: "gojo", path: "/whalestickers/gojo.png", width: 128, height: 130}
      ])

    {:ok, document} = Floki.parse_fragment(normalized)
    [sticker] = Floki.find(document, ~s(img[src="/whalestickers/gojo.png"]))
    [external] = Floki.find(document, ~s(img[src="https://example.com/unrelated.png"]))

    assert Floki.attribute(sticker, "width") == ["128"]
    assert Floki.attribute(sticker, "height") == ["130"]
    assert Floki.attribute(sticker, "loading") == ["eager"]
    assert Floki.attribute(sticker, "decoding") == ["async"]
    assert Floki.attribute(external, "width") == []
    assert Floki.attribute(external, "loading") == []
  end
end
