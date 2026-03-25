defmodule Eirinchan.RulesPage do
  @moduledoc false

  import Phoenix.Template, only: [render_to_string: 4]

  def default_body do
    render_to_string(EirinchanWeb.PageHTML, "rules_body", "html", [])
  end

  def normalize_body(html) when is_binary(html) do
    trimmed = String.trim(html)

    cond do
      trimmed == "" ->
        default_body()

      String.contains?(trimmed, "<!doctype html") or String.contains?(trimmed, "<html") ->
        extract_fragment(trimmed)

      true ->
        trimmed
    end
  end

  def normalize_body(other), do: other

  defp extract_fragment(html) do
    cond do
      capture =
          capture_regex(
            html,
            ~r|(<div class="box-wrap(?: faq-page-shell)?(?: rules-page-shell)?">.*?</div>\s*)<hr|s
          ) ->
        String.trim(capture)

      capture = capture_regex(html, ~r|<body\b[^>]*>(.*)</body>|s) ->
        capture
        |> strip_shell_wrappers()
        |> String.trim()
        |> case do
          "" -> default_body()
          value -> value
        end

      true ->
        default_body()
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
    |> then(&Regex.replace(~r|<header>.*?</header>|s, &1, ""))
    |> then(&Regex.replace(~r|<hr\s*/?>|i, &1, ""))
  end
end
