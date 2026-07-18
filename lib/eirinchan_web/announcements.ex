defmodule EirinchanWeb.Announcements do
  @moduledoc false

  alias Eirinchan.AprilFoolsTeams
  alias Eirinchan.GlobalMessageRefreshWorker
  alias Eirinchan.NewsBlotter
  alias Eirinchan.Settings
  alias Eirinchan.Stats
  alias Eirinchan.Tf2PlayerCount
  alias EirinchanWeb.FragmentCache
  alias EirinchanWeb.HtmlSanitizer

  @default_aggregate_cache_seconds 30

  @refresh_cache_namespaces [
    :announcement_global_message,
    :tf2_player_count,
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
    |> maybe_replace_tf2_placeholders(opts)
    |> maybe_replace_posts_perhour(opts)
    |> maybe_replace_threads_perhour(opts)
    |> maybe_replace_users_10minutes(opts)
    |> maybe_replace_team_placeholders()
  end

  defp maybe_replace_tf2_placeholders(message, opts) do
    if tf2_placeholder?(message) do
      stats = cached_tf2_stats(opts)

      message
      |> maybe_render_tf2_conditionals(stats)
      |> String.replace("{tf2_display}", stats.display)
    else
      message
    end
  end

  defp tf2_placeholder?(message) do
    String.contains?(message, "{tf2_display}") or
      String.contains?(message, "{if tf2_display")
  end

  defp cached_tf2_stats(opts) do
    now = Keyword.get(opts, :tf2_now, System.system_time(:second))
    cache_bucket = div(now, Tf2PlayerCount.cache_seconds())

    FragmentCache.fetch_or_store({:tf2_player_count, cache_bucket}, fn ->
      fetch_opts =
        case Keyword.get(opts, :tf2_fetcher) do
          fetcher when is_function(fetcher, 0) -> [fetcher: fetcher]
          _ -> []
        end

      case Tf2PlayerCount.fetch(fetch_opts) do
        {:ok, stats} -> stats
        {:error, _reason} -> Tf2PlayerCount.unavailable()
      end
    end)
  end

  defp maybe_render_tf2_conditionals(message, stats) do
    if String.contains?(message, "{if tf2_display") do
      message
      |> String.replace("\\n", "\n")
      |> String.split(~r/\r\n|\r|\n/u, trim: false)
      |> render_tf2_conditional_lines(stats.player_count > 0, [])
      |> Enum.join("\n")
    else
      message
    end
  end

  defp render_tf2_conditional_lines([line, next_line | rest], show?, rendered) do
    case tf2_conditional(line) do
      {:following_line, prefix} ->
        emitted_lines =
          case {prefix, show?} do
            {"", true} -> [next_line]
            {"", false} -> []
            {prefix, true} -> [prefix, next_line]
            {prefix, false} -> [prefix]
          end

        rendered = Enum.reduce(emitted_lines, rendered, fn emitted, acc -> [emitted | acc] end)
        render_tf2_conditional_lines(rest, show?, rendered)

      {:inline, prefix, conditional_text} ->
        rendered =
          prefix
          |> inline_conditional_value(conditional_text, show?)
          |> maybe_prepend_rendered(rendered)

        render_tf2_conditional_lines([next_line | rest], show?, rendered)

      :error ->
        render_tf2_conditional_lines([next_line | rest], show?, [line | rendered])
    end
  end

  defp render_tf2_conditional_lines([line], show?, rendered) do
    rendered =
      case tf2_conditional(line) do
        {:following_line, ""} ->
          rendered

        {:following_line, prefix} ->
          [prefix | rendered]

        {:inline, prefix, conditional_text} ->
          prefix
          |> inline_conditional_value(conditional_text, show?)
          |> maybe_prepend_rendered(rendered)

        :error ->
          [line | rendered]
      end

    Enum.reverse(rendered)
  end

  defp render_tf2_conditional_lines([], _show?, rendered), do: Enum.reverse(rendered)

  defp inline_conditional_value(prefix, conditional_text, true), do: prefix <> conditional_text

  defp inline_conditional_value(prefix, _conditional_text, false),
    do: String.trim_trailing(prefix)

  defp maybe_prepend_rendered("", rendered), do: rendered
  defp maybe_prepend_rendered(value, rendered), do: [value | rendered]

  defp tf2_conditional(line) do
    case Regex.run(
           ~r/^(.*?)\{if\s+tf2_display\s*>\s*0\s*\}(.*)$/u,
           line,
           capture: :all_but_first
         ) do
      [prefix, suffix] ->
        if String.trim(suffix) == "" do
          {:following_line, String.trim_trailing(prefix)}
        else
          {:inline, prefix, suffix}
        end

      _ ->
        :error
    end
  end

  defp cacheable_aggregate_placeholders?(message, opts) do
    case stats_placeholders(message) do
      %{board_scoped?: true, team_scoped?: false} ->
        aggregate_board_ids(opts) != []

      %{team_scoped?: true} ->
        false

      _ ->
        false
    end
  end

  defp stats_placeholders(message) do
    %{
      board_scoped?:
        String.contains?(message, "{stats.posts_perhour}") or
          String.contains?(message, "{stats.threads_perhour}") or
          String.contains?(message, "{stats.users_10minutes}"),
      team_scoped?:
        Regex.match?(
          ~r/\{stats\.team_\d+\.(?:name|display_name|colour|color|html_colour|post_count)\}/u,
          message
        )
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

  defp maybe_replace_team_placeholders(message) do
    Regex.replace(
      ~r/\{stats\.(team_\d+)\.(name|display_name|colour|color|html_colour|post_count)\}/u,
      message,
      fn _full, team_var, field ->
        case Stats.team_variable(team_var) do
          {_team_id, display_name, html_colour, post_count} ->
            team_field_value(field, display_name, html_colour, post_count)

          _ ->
            "{stats.#{team_var}.#{field}}"
        end
      end
    )
  end

  defp team_field_value(field, display_name, html_colour, post_count)

  defp team_field_value(field, display_name, _html_colour, _post_count)
       when field in ["name", "display_name"],
       do: display_name

  defp team_field_value(field, _display_name, html_colour, _post_count)
       when field in ["colour", "color", "html_colour"],
       do: html_colour

  defp team_field_value("post_count", _display_name, _html_colour, post_count),
    do: AprilFoolsTeams.silly_post_count(post_count)
end
