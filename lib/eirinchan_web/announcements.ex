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
        rendered_message = render_message_fragment(message)

        if Keyword.get(opts, :surround_hr, false) do
          """
          <hr />
          <div class="blotter">#{rendered_message}</div>
          <hr />
          """
          |> String.trim()
        else
          ~s(<div class="blotter">#{rendered_message}</div>)
        end
    end
  end

  def render_message_fragment(message) when is_binary(message) do
    message
    |> HtmlSanitizer.sanitize_fragment()
    |> String.replace("\\n", "<br />")
    |> String.replace(~r/\r\n|\r|\n/, "<br />")
  end

  def render_message_fragment(other), do: render_message_fragment(to_string(other))

  defp expand_placeholders(message, opts) do
    message
    |> maybe_replace_posts_perhour(opts)
    |> maybe_replace_users_10minutes()
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

  defp maybe_replace_posts_perhour(message, opts) do
    if String.contains?(message, "{stats.posts_perhour}") do
      String.replace(message, "{stats.posts_perhour}", posts_perhour_placeholder(opts))
    else
      message
    end
  end

  defp maybe_replace_users_10minutes(message) do
    if String.contains?(message, "{stats.users_10minutes}") do
      String.replace(message, "{stats.users_10minutes}", Stats.users_10minutes() |> Integer.to_string())
    else
      message
    end
  end
end
