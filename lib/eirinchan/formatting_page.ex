defmodule Eirinchan.FormattingPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]

  def default_body(sticker_entries \\ []) do
    render_to_string(EirinchanWeb.PageHTML, "formatting_body", "html",
      sticker_entries: sticker_entries
    )
  end

  def normalize_body(html, sticker_entries \\ [])
  def normalize_body(html, sticker_entries) when is_binary(html) do
    trimmed = String.trim(html)

    cond do
      trimmed == "" ->
        default_body(sticker_entries)

      String.contains?(trimmed, "<!doctype html") or String.contains?(trimmed, "<html") ->
        extract_fragment(trimmed, sticker_entries)

      true ->
        trimmed
    end
  end

  def normalize_body(other, _sticker_entries), do: other

  defp extract_fragment(html, sticker_entries) do
    cond do
      capture =
          capture_regex(html, ~r|(<div class="box-wrap(?: faq-page-shell)?(?: formatting-page-shell)?">.*?</div>\s*)<footer|s) ->
        String.trim(capture)

      capture = capture_regex(html, ~r|<body\b[^>]*>(.*)</body>|s) ->
        capture
        |> strip_shell_wrappers()
        |> String.trim()
        |> case do
          "" -> default_body(sticker_entries)
          value -> value
        end

      true ->
        default_body(sticker_entries)
    end
  end

  defp capture_regex(html, regex) do
    case Regex.run(regex, html, capture: :all_but_first) do
      [capture | _rest] -> capture
      _ -> nil
    end
  end

  defp strip_shell_wrappers(body) do
    body
    |> then(&Regex.replace(~r|<div class="boardlist(?: bottom)?">.*?</div>|s, &1, ""))
    |> then(&Regex.replace(~r|<a id="top"></a>|, &1, ""))
    |> then(&Regex.replace(~r|<a id="bottom"></a>|, &1, ""))
    |> then(&Regex.replace(~r|<div class="styles">.*?</div>|s, &1, ""))
    |> then(&Regex.replace(~r|<footer>.*?</footer>|s, &1, ""))
    |> then(&Regex.replace(~r|<script\b[^>]*>.*?</script>|s, &1, ""))
    |> then(&Regex.replace(~r|<style\b[^>]*>.*?</style>|s, &1, ""))
  end
end
