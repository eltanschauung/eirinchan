defmodule Eirinchan.NewsBlotter do
  @moduledoc """
  Renders the PSA/news blotter configured from instance settings.
  """

  def entries(config) when is_map(config) do
    config
    |> Map.get(:news_blotter_entries, Map.get(config, "news_blotter_entries", []))
    |> List.wrap()
    |> Enum.map(&normalize_entry/1)
    |> Enum.filter(& &1)
    |> apply_limit(Map.get(config, :news_blotter_limit, Map.get(config, "news_blotter_limit", 15)))
  end

  def render_html(config) when is_map(config) do
    entries = entries(config)

    case entries do
      [] ->
        ""

      _ ->
        latest_date =
          entries
          |> List.first()
          |> Map.get(:date, "")

        rows =
          entries
          |> Enum.map(fn %{date: date, message: message} ->
            "<tr><td>#{escape(date)}</td><td>#{message}</td></tr>"
          end)
          |> Enum.join("")

        """
        <div id=\"blotterContainer\" style=\"text-align: center;\">
          <div class=\"news-button\" data-toggle-news role=\"button\" tabindex=\"0\">[View News - #{escape(latest_date)}]</div>
          <hr style=\"width: 100%; max-width: 500px;\">
          <div class=\"news-blotter\" style=\"width: 100%; max-width: 400px; margin: 0 auto;\">
            <h1 style=\"font-size: 16pt; letter-spacing: -1px;\">PSA Blotter</h1>
            <table class=\"subtitle\" style=\"font-size: 8pt; color: maroon;\">#{rows}</table>
            <hr style=\"width: 100%; max-width: 500px;\">
          </div>
        </div>
        """
        |> String.trim()
    end
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

  defp escape(value) do
    value
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
