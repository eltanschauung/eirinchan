defmodule Eirinchan.LegacyPageBody do
  @moduledoc false

  @shell_wrappers [
    ~r|<div class="boardlist(?: bottom)?">.*?</div>|s,
    ~r|<a id="top"></a>|,
    ~r|<a id="bottom"></a>|,
    ~r|<div class="styles">.*?</div>|s,
    ~r|<footer>.*?</footer>|s,
    ~r|<script\b[^>]*>.*?</script>|s
  ]

  @optional_wrappers %{
    style: ~r|<style\b[^>]*>.*?</style>|s,
    header: ~r|<header>.*?</header>|s,
    horizontal_rule: ~r|<hr\s*/?>|i
  }

  def normalize(html, default, opts \\ [])

  def normalize(html, default, opts) when is_binary(html) and is_function(default, 0) do
    trimmed = String.trim(html)

    cond do
      trimmed == "" -> default.()
      full_document?(trimmed) -> extract_fragment(trimmed, default, opts)
      true -> trimmed
    end
  end

  def normalize(other, _default, _opts), do: other

  defp full_document?(html) do
    String.contains?(html, "<!doctype html") or String.contains?(html, "<html")
  end

  defp extract_fragment(html, default, opts) do
    content_regex = Keyword.get(opts, :content_regex)

    case capture_regex(html, content_regex) do
      capture when is_binary(capture) ->
        String.trim(capture)

      nil ->
        html
        |> capture_regex(~r|<body\b[^>]*>(.*)</body>|s)
        |> normalize_body_capture(default, Keyword.get(opts, :strip, []))
    end
  end

  defp normalize_body_capture(nil, default, _optional_wrappers), do: default.()

  defp normalize_body_capture(body, default, optional_wrappers) do
    value =
      (@shell_wrappers ++ Enum.map(optional_wrappers, &Map.fetch!(@optional_wrappers, &1)))
      |> Enum.reduce(body, fn regex, value -> Regex.replace(regex, value, "") end)
      |> String.trim()

    if value == "", do: default.(), else: value
  end

  defp capture_regex(_html, nil), do: nil

  defp capture_regex(html, regex) do
    case Regex.run(regex, html, capture: :all_but_first) do
      [capture | _rest] -> capture
      _ -> nil
    end
  end
end
