defmodule Eirinchan.EmojiShortcodesTest do
  use ExUnit.Case, async: true

  alias Eirinchan.EmojiShortcodes

  test "ships the complete built-in shortcode set" do
    assert map_size(EmojiShortcodes.entries()) == 100

    assert EmojiShortcodes.entries()
           |> Map.take(["sob", "heart_on_fire", "eyes", "v", "bicep", "zap"]) == %{
             "sob" => "😭",
             "heart_on_fire" => "❤️‍🔥",
             "eyes" => "👀",
             "v" => "✌️",
             "bicep" => "💪",
             "zap" => "⚡"
           }
  end

  test "replaces known shortcodes in one pass and preserves unknown text" do
    assert EmojiShortcodes.replace(
             "look :eyes: :heart: :heart_on_fire: :100: :v: :unknown: :EYES:"
           ) == "look 👀 ❤️ ❤️‍🔥 💯 ✌️ :unknown: :EYES:"
  end

  test "replaces every configured shortcode" do
    entries =
      EmojiShortcodes.entries()
      |> Enum.sort()

    body = Enum.map_join(entries, " ", fn {name, _emoji} -> ":#{name}:" end)
    expected = Enum.map_join(entries, " ", fn {_name, emoji} -> emoji end)

    assert EmojiShortcodes.replace(body) == expected
  end

  test "does not replace post bodies when emojis is false" do
    attrs = %{"body" => "example :eyes: :v: :bicep:"}

    assert EmojiShortcodes.replace_body(attrs, %{emojis: false}) == attrs

    assert EmojiShortcodes.replace_body(attrs, %{emojis: true}) == %{
             "body" => "example 👀 ✌️ 💪"
           }
  end
end
