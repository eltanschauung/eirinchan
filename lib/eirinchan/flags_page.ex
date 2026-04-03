defmodule Eirinchan.FlagsPage do
  @moduledoc false

  def default_body do
    """
    Pick custom flags for your posts.
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

  def article_html(html) when is_binary(html) do
    normalized = normalize_body(html)

    if placeholder_body?(normalized), do: nil, else: blank_to_nil(normalized)
  end

  def article_html(_html), do: nil

  def description_html do
    """
    <p1>To rizz your posts, write flag names into the field below, separated by a comma. "country" is a special case that displays your country. If the field is empty, you'll have a US flag.</p1><br><br>
    """
    |> String.trim()
  end

  def footer_html do
    """
    <p1><i>New feature:</i> You can click the flags.</p1>
    """
    |> String.trim()
  end

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

  defp placeholder_body?(value) when is_binary(value) do
    String.trim(value) in ["", "Flags", "Custom flags", "Pick custom flags for your posts."]
  end

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end
end
