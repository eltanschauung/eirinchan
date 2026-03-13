defmodule EirinchanWeb.Announcements do
  @moduledoc false

  alias Eirinchan.NewsBlotter
  alias EirinchanWeb.HtmlSanitizer

  def news_blotter_html(config) when is_map(config) do
    NewsBlotter.render_html(config)
  end

  def global_message(config) when is_map(config) do
    case Map.get(config, :global_message) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  def global_message_html(config, opts \\ []) when is_map(config) do
    case global_message(config) do
      nil ->
        ""

      message ->
        sanitized_message = HtmlSanitizer.sanitize_fragment(message)

        if Keyword.get(opts, :surround_hr, false) do
          """
          <hr />
          <div class="blotter">#{sanitized_message}</div>
          <hr />
          """
          |> String.trim()
        else
          ~s(<div class="blotter">#{sanitized_message}</div>)
        end
    end
  end
end
