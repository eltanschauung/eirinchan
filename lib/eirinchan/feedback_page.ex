defmodule Eirinchan.FeedbackPage do
  @moduledoc false

  def default_body do
    """
    <p>Submit any kind of feedback you want. Feedback is anonymous.</p>
    """
    |> String.trim()
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
    case Regex.run(~r|<body\b[^>]*>(.*)</body>|s, html, capture: :all_but_first) do
      [capture | _rest] ->
        capture
        |> strip_shell_wrappers()
        |> String.trim()
        |> case do
          "" -> default_body()
          value -> value
        end

      _ ->
        default_body()
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
  end
end
