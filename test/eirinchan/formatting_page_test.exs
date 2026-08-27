defmodule Eirinchan.FormattingPageTest do
  use ExUnit.Case, async: true

  alias Eirinchan.FormattingPage

  test "refreshes the sticker columns in a stored formatting page" do
    stored_body =
      FormattingPage.default_body([
        %{token: "old", path: "/stickers/old.png", width: 100, height: 100}
      ])

    normalized =
      FormattingPage.normalize_body(stored_body, [
        %{token: "new", path: "/stickers/new.png", width: 120, height: 120}
      ])

    refute normalized =~ "/stickers/old.png"
    assert normalized =~ "/stickers/new.png"
  end

  test "upgrades stored sticker markup without altering unrelated images" do
    html = """
    <div>
      <img src="/stickers/example.png" title="example">
      <img src="https://example.com/unrelated.png" title="unrelated">
    </div>
    """

    normalized =
      FormattingPage.normalize_body(html, [
        %{token: "example", path: "/stickers/example.png", width: 128, height: 130}
      ])

    {:ok, document} = Floki.parse_fragment(normalized)
    [sticker] = Floki.find(document, ~s(img[src="/stickers/example.png"]))
    [external] = Floki.find(document, ~s(img[src="https://example.com/unrelated.png"]))

    assert Floki.attribute(sticker, "width") == ["128"]
    assert Floki.attribute(sticker, "height") == ["130"]
    assert Floki.attribute(sticker, "loading") == ["eager"]
    assert Floki.attribute(sticker, "decoding") == ["async"]
    assert Floki.attribute(external, "width") == []
    assert Floki.attribute(external, "loading") == []
  end
end
