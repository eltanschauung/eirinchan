defmodule Eirinchan.StaticImageDimensionsTest do
  use ExUnit.Case, async: true

  alias Eirinchan.StaticImageDimensions

  test "reads dimensions from supported image headers" do
    png =
      <<
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        13::32,
        "IHDR",
        30::32,
        80::32
      >>

    gif = <<"GIF89a", 127::little-16, 98::little-16>>

    jpeg =
      <<
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x04,
        0x00,
        0x00,
        0xFF,
        0xC0,
        0x00,
        0x08,
        0x08,
        0x00,
        0x62,
        0x00,
        0x7F
      >>

    assert StaticImageDimensions.from_binary(png) == {30, 80}
    assert StaticImageDimensions.from_binary(gif) == {127, 98}
    assert StaticImageDimensions.from_binary(jpeg) == {127, 98}
    assert StaticImageDimensions.from_binary("not an image") == nil
  end

  test "resolves repository static images without allowing path traversal" do
    assert StaticImageDimensions.for_static_path("/reisen_up.png") == {30, 80}
    assert StaticImageDimensions.for_static_path("/tewi_down.png") == {30, 80}
    assert StaticImageDimensions.for_static_path("/../mix.exs") == nil
    assert StaticImageDimensions.for_static_path("https://example.com/image.png") == nil
  end
end
