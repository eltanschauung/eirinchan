defmodule Eirinchan.NewsBlotter do
  @moduledoc """
  Renders the PSA/news blotter configured from instance settings.
  """

  alias EirinchanWeb.HtmlSanitizer

  def entries(config, opts \\ []) when is_map(config) do
    limit = Keyword.get(opts, :limit, entry_limit(config))

    config
    |> Map.get(:news_blotter_entries, Map.get(config, "news_blotter_entries", []))
    |> List.wrap()
    |> Enum.map(&normalize_entry/1)
    |> Enum.filter(& &1)
    |> apply_limit(limit)
  end

  def preview_entries(config) when is_map(config) do
    entries(config, limit: preview_limit(config))
  end

  def preview_limit(config) when is_map(config) do
    config
    |> Map.get(:news_maxentries, Map.get(config, "news_maxentries", 10))
    |> normalize_positive_limit(10)
  end

  def entry_limit(config) when is_map(config) do
    config
    |> Map.get(:news_blotter_limit, Map.get(config, "news_blotter_limit", 100))
    |> normalize_positive_limit(100)
  end

  def button_label(config) when is_map(config) do
    config
    |> Map.get(
      :news_blotter_button_label,
      Map.get(config, "news_blotter_button_label", "View News - {date}")
    )
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "View News - {date}"
      value -> value
    end
  end

  def render_html(config) when is_map(config) do
    entries = preview_entries(config)

    case entries do
      [] ->
        ""

      _ ->
        latest_date =
          entries
          |> List.first()
          |> Map.get(:date, "")

        button_label =
          config
          |> button_label()
          |> String.replace("{date}", latest_date)

        rows =
          entries
          |> Enum.map(fn %{date: date, message: message} ->
            "<tr><td>#{escape(date)}</td><td>#{HtmlSanitizer.sanitize_fragment(message)}</td></tr>"
          end)
          |> Enum.join("")

        """
        <div id=\"blotterContainer\" style=\"text-align: center;\">
          <div class=\"news-button\" data-toggle-news role=\"button\" tabindex=\"0\">[#{escape(button_label)}]</div>
          <hr style=\"width: 100%; max-width: 500px;\">
          <div class=\"news-blotter\" style=\"width: 100%; max-width: 400px; margin: 0 auto;\">
            <h1 style=\"font-size: 16pt; letter-spacing: -1px;\">PSA Blotter</h1>
            <table class=\"subtitle\" style=\"font-size: 8pt; color: maroon;\">#{rows}</table>
            <hr style=\"width: 100%; max-width: 500px;\">
            <a href=\"/news\" class=\"unimportant2\">View All News</a>
          </div>
        </div>
        """
        |> String.trim()
    end
  end

  def render_message_html(message) when is_binary(message) do
    HtmlSanitizer.sanitize_fragment(message)
  end

  defp normalize_entry(%{"date" => date, "message" => message}) do
    normalize_entry(%{date: date, message: message})
  end

  defp normalize_entry(%{date: date, message: message})
       when is_binary(date) and is_binary(message) do
    trimmed_date = String.trim(date)
    trimmed_message = String.trim(message)

    if trimmed_date == "" or trimmed_message == "" do
      nil
    else
      %{date: trimmed_date, message: trimmed_message}
    end
  end

  defp normalize_entry([date, message]) when is_binary(date) and is_binary(message) do
    normalize_entry(%{date: date, message: message})
  end

  defp normalize_entry({date, message}) when is_binary(date) and is_binary(message) do
    normalize_entry(%{date: date, message: message})
  end

  defp normalize_entry(_entry), do: nil

  defp apply_limit(entries, limit) when is_integer(limit) and limit > 0 do
    Enum.take(entries, limit)
  end

  defp apply_limit(entries, _limit), do: entries

  defp normalize_positive_limit(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_positive_limit(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp normalize_positive_limit(_, default), do: default

  defp escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
