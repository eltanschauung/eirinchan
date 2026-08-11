defmodule Eirinchan.EmojiShortcodes do
  @moduledoc """
  Converts the built-in post-body emoji shortcodes to Unicode before storage.
  """

  @shortcodes %{
    "100" => "💯",
    "alien" => "👽",
    "cross" => "😠",
    "aquarius" => "♒",
    "aries" => "♈",
    "bicep" => "💪",
    "black_heart" => "🖤",
    "blush" => "😊",
    "blue_heart" => "💙",
    "broken_heart" => "💔",
    "butterfly" => "🦋",
    "cancer" => "♋",
    "capricorn" => "♑",
    "cat" => "🐱",
    "check" => "✅",
    "cherry_blossom" => "🌸",
    "clap" => "👏",
    "clinking" => "🥂",
    "clown" => "🤡",
    "crossed_fingers" => "🤞",
    "cry" => "😢",
    "dancer" => "💃",
    "dizzy_face" => "😵",
    "dog" => "🐶",
    "exclamation" => "❗",
    "exploding_head" => "🤯",
    "expressionless" => "😑",
    "eyes" => "👀",
    "facepalm" => "🤦",
    "fire" => "🔥",
    "fist" => "✊",
    "flushed" => "😳",
    "ghost" => "👻",
    "gemini" => "♊",
    "goat" => "🐐",
    "green_heart" => "💚",
    "grin" => "😁",
    "handshake" => "🤝",
    "hear_no_evil" => "🙉",
    "heart" => "❤️",
    "heart_eyes" => "😍",
    "heart_on_fire" => "❤️‍🔥",
    "joy" => "😂",
    "kissing_heart" => "😘",
    "laughing" => "😆",
    "leo" => "♌",
    "libra" => "♎",
    "love_you" => "🤟",
    "mag_right" => "🔎",
    "melting_face" => "🫠",
    "moon" => "🌙",
    "nail_care" => "💅",
    "nauseated" => "🤢",
    "neutral_face" => "😐",
    "ok_hand" => "👌",
    "orange_heart" => "🧡",
    "partying_face" => "🥳",
    "pink_heart" => "🩷",
    "pisces" => "♓",
    "pleading" => "🥺",
    "point_down" => "👇",
    "point_left" => "👈",
    "point_right" => "👉",
    "point_up" => "👆",
    "poop" => "💩",
    "prayer" => "🙏",
    "purple_heart" => "💜",
    "question" => "❓",
    "rage" => "😡",
    "rainbow" => "🌈",
    "raised_hands" => "🙌",
    "revolving_hearts" => "💞",
    "robot" => "🤖",
    "rock_on" => "🤘",
    "rose" => "🌹",
    "running" => "🏃",
    "sagittarius" => "♐",
    "salute" => "🫡",
    "scorpio" => "♏",
    "see_no_evil" => "🙈",
    "shrug" => "🤷",
    "skull" => "💀",
    "sleeping" => "😴",
    "slight_smile" => "🙂",
    "smile" => "😄",
    "snowflake" => "❄️",
    "sob" => "😭",
    "sparkles" => "✨",
    "sparkling_heart" => "💖",
    "speak_no_evil" => "🙊",
    "star" => "⭐",
    "sunflower" => "🌻",
    "sunglasses" => "😎",
    "sunny" => "☀️",
    "sweat" => "😓",
    "sweat_smile" => "😅",
    "taurus" => "♉",
    "thumbsdown" => "👎",
    "thumbsup" => "👍",
    "two_hearts" => "💕",
    "unamused" => "😒",
    "upside_down" => "🙃",
    "v" => "✌️",
    "virgo" => "♍",
    "warning" => "⚠️",
    "wave" => "👋",
    "white_heart" => "🤍",
    "wink" => "😉",
    "writing_hand" => "✍️",
    "x" => "❌",
    "yellow_heart" => "💛",
    "zap" => "⚡"
  }

  @shortcode_regex ~r/:([a-z0-9_]+):/u

  @spec entries() :: %{binary() => binary()}
  def entries, do: @shortcodes

  @spec replace_body(map(), map()) :: map()
  def replace_body(attrs, %{emojis: false}) when is_map(attrs), do: attrs

  def replace_body(attrs, _config) when is_map(attrs) do
    Map.update(attrs, "body", nil, fn
      body when is_binary(body) -> replace(body)
      body -> body
    end)
  end

  @spec replace(binary()) :: binary()
  def replace(body) when is_binary(body) do
    Regex.replace(@shortcode_regex, body, fn shortcode, name ->
      Map.get(@shortcodes, name, shortcode)
    end)
  end
end
