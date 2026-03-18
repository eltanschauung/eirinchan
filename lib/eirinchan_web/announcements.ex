defmodule EirinchanWeb.Announcements do
  @moduledoc false

  alias Eirinchan.NewsBlotter
  alias Eirinchan.Stats
  alias EirinchanWeb.HtmlSanitizer

  def news_blotter_html(config) when is_map(config) do
    NewsBlotter.render_html(config)
  end

  def global_message(config, opts \\ []) when is_map(config) do
    case Map.get(config, :global_message) do
      value when is_binary(value) and value != "" -> expand_placeholders(value, opts)
      _ -> nil
    end
  end

  def global_message_html(config, opts \\ []) when is_map(config) do
    case global_message(config, opts) do
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

  defp expand_placeholders(message, opts) do
    if String.contains?(message, "{stats.posts_perhour}") do
      String.replace(message, "{stats.posts_perhour}", posts_perhour_placeholder(opts))
    else
      message
    end
  end

  defp posts_perhour_placeholder(opts) do
    cond do
      is_map(opts[:board]) and Map.has_key?(opts[:board], :id) ->
        opts[:board]
        |> Stats.posts_perhour()
        |> Integer.to_string()

      is_list(opts[:board_ids]) and opts[:board_ids] != [] ->
        opts[:board_ids]
        |> Stats.posts_perhour()
        |> Integer.to_string()

      true ->
        "{stats.posts_perhour}"
    end
  end
end
