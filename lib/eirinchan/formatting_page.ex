defmodule Eirinchan.FormattingPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]
  alias Eirinchan.LegacyPageBody

  def default_body(sticker_entries \\ []) do
    render_to_string(EirinchanWeb.PageHTML, "formatting_body", "html",
      left_stickers: left_stickers(sticker_entries),
      right_stickers: right_stickers(sticker_entries)
    )
  end

  def normalize_body(html, sticker_entries \\ [])

  def normalize_body(html, sticker_entries) do
    LegacyPageBody.normalize(html, fn -> default_body(sticker_entries) end,
      content_regex:
        ~r|(<div class="box-wrap(?: faq-page-shell)?(?: formatting-page-shell)?">.*?</div>\s*)<footer|s,
      strip: [:style]
    )
  end

  defp left_stickers(sticker_entries) do
    stickers = ordered_stickers(sticker_entries)
    Enum.take(stickers, div(length(stickers) + 1, 2))
  end

  defp right_stickers(sticker_entries) do
    stickers = ordered_stickers(sticker_entries)
    Enum.drop(stickers, div(length(stickers) + 1, 2))
  end

  defp ordered_stickers(sticker_entries) do
    Enum.sort_by(sticker_entries, &sticker_token/1)
  end

  defp sticker_token(%{token: token}) when is_binary(token), do: token
  defp sticker_token(%{"token" => token}) when is_binary(token), do: token
  defp sticker_token(_sticker), do: ""
end
