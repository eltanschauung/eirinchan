defmodule EirinchanWeb.Announcements do
  @moduledoc false

  alias Eirinchan.GlobalMessageRefreshWorker
  alias Eirinchan.NewsBlotter
  alias Eirinchan.Settings
  alias Eirinchan.Stats
  alias EirinchanWeb.FragmentCache
  alias EirinchanWeb.HtmlSanitizer

  @default_aggregate_cache_seconds 30

  @refresh_cache_namespaces [
    :announcement_global_message,
    :board_fragment_md5,
    :thread_fragment_md5
  ]

  def refresh_cache do
    FragmentCache.delete_namespaces(@refresh_cache_namespaces)
  end

  def news_blotter_html(config) when is_map(config) do
    NewsBlotter.render_html(config)
  end

  def global_message(config, opts \\ []) when is_map(config) do
    opts =
      Keyword.put_new(
        opts,
        :aggregate_cache_seconds,
        GlobalMessageRefreshWorker.interval_seconds(config)
      )

    case Map.get(config, :global_message) do
      value when is_binary(value) and value != "" -> expand_text(value, opts)
      _ -> nil
    end
  end

  def expand_text(value, opts \\ []) when is_binary(value) do
    expand_placeholders_cached(value, opts)
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

  defp expand_placeholders_cached(message, opts) do
    if cacheable_aggregate_placeholders?(message, opts) do
      FragmentCache.fetch_or_store(aggregate_cache_key(message, opts), fn ->
        expand_placeholders(message, opts)
      end)
    else
      expand_placeholders(message, opts)
    end
  end

  defp expand_placeholders(message, opts) do
    message
    |> maybe_replace_posts_perhour(opts)
    |> maybe_replace_threads_perhour(opts)
    |> maybe_replace_users_10minutes(opts)
  end

  defp cacheable_aggregate_placeholders?(message, opts) do
    case stats_placeholders(message) do
      %{board_scoped?: true} ->
        aggregate_board_ids(opts) != []

      _ ->
        false
    end
  end

  defp stats_placeholders(message) do
    %{
      board_scoped?:
        String.contains?(message, "{stats.posts_perhour}") or
          String.contains?(message, "{stats.threads_perhour}") or
          String.contains?(message, "{stats.users_10minutes}")
    }
  end

  defp aggregate_cache_key(message, opts) do
    {
      :announcement_global_message,
      message,
      opts[:surround_hr] || false,
      aggregate_board_ids(opts),
      div(aggregate_cache_now(opts), aggregate_cache_seconds(opts))
    }
  end

  defp aggregate_board_ids(opts) do
    case opts[:board] do
      %{id: board_id} when is_integer(board_id) ->
        [board_id]

      _other ->
        opts[:board_ids]
        |> List.wrap()
        |> Enum.filter(&is_integer/1)
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  defp aggregate_cache_seconds(opts) do
    case opts[:aggregate_cache_seconds] do
      seconds when is_integer(seconds) and seconds > 0 -> seconds
      _other -> configured_aggregate_cache_seconds()
    end
  end

  defp configured_aggregate_cache_seconds do
    case Map.get(
           Settings.effective_instance_config(),
           :announcement_cache_seconds,
           @default_aggregate_cache_seconds
         ) do
      seconds when is_integer(seconds) and seconds > 0 -> min(seconds, 3_600)
      _other -> @default_aggregate_cache_seconds
    end
  end

  defp aggregate_cache_now(opts) do
    case opts[:aggregate_now] do
      now when is_integer(now) and now >= 0 -> now
      _other -> System.system_time(:second)
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

  defp maybe_replace_posts_perhour(message, opts) do
    if String.contains?(message, "{stats.posts_perhour}") do
      String.replace(message, "{stats.posts_perhour}", posts_perhour_placeholder(opts))
    else
      message
    end
  end

  defp maybe_replace_threads_perhour(message, opts) do
    if String.contains?(message, "{stats.threads_perhour}") do
      String.replace(message, "{stats.threads_perhour}", threads_perhour_placeholder(opts))
    else
      message
    end
  end

  defp threads_perhour_placeholder(opts) do
    cond do
      is_map(opts[:board]) and Map.has_key?(opts[:board], :id) ->
        opts[:board]
        |> Stats.threads_perhour()
        |> Integer.to_string()

      is_list(opts[:board_ids]) and opts[:board_ids] != [] ->
        opts[:board_ids]
        |> Stats.threads_perhour()
        |> Integer.to_string()

      true ->
        "{stats.threads_perhour}"
    end
  end

  defp maybe_replace_users_10minutes(message, opts) do
    if String.contains?(message, "{stats.users_10minutes}") do
      String.replace(
        message,
        "{stats.users_10minutes}",
        users_10minutes(opts) |> Integer.to_string()
      )
    else
      message
    end
  end

  defp users_10minutes(opts) do
    case opts[:users_10minutes_fetcher] do
      fetcher when is_function(fetcher, 0) -> fetcher.()
      _other -> Stats.users_10minutes()
    end
  end
end
