defmodule EirinchanWeb.PublicControllerHelpers do
  @moduledoc false

  alias Eirinchan.ThreadWatcher
  alias EirinchanWeb.FragmentHash
  alias EirinchanWeb.PublicShell

  @empty_watcher_metrics %{watcher_count: 0, watcher_unread_count: 0, watcher_you_count: 0}
  @public_extra_stylesheets ["/stylesheets/eirinchan-public.css", "/stylesheets/eirinchan-bant.css"]

  def fragment_options(params) do
    [fragment?: fragment_request?(params), fragment_md5?: fragment_md5_request?(params)]
  end

  def fragment_request?(%{"fragment" => value}) when value in ["1", "true", "yes"], do: true
  def fragment_request?(_params), do: false

  def fragment_md5_request?(%{"fragment" => "md5"}), do: true
  def fragment_md5_request?(_params), do: false

  def render_fragment_md5(view, template, assigns, cache_key) do
    FragmentHash.md5(view, template, assigns, cache_key: cache_key)
  end

  def dynamic_fragment_stamp(assigns, watch_key) do
    {
      own_post_ids_stamp(Keyword.get(assigns, :own_post_ids, MapSet.new())),
      Keyword.get(assigns, :show_yous, false),
      :erlang.phash2(Keyword.get(assigns, watch_key, %{})),
      moderator_stamp(Keyword.get(assigns, :current_moderator)),
      Keyword.get(assigns, :secure_manage_token),
      Keyword.get(assigns, :mobile_client?, false)
    }
  end

  def watcher_metrics(conn) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) -> ThreadWatcher.watch_metrics(token)
      _ -> @empty_watcher_metrics
    end
  end

  def thread_watch_state(conn, board_uri) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) -> ThreadWatcher.watch_state_for_board(token, board_uri)
      _ -> %{}
    end
  end

  def thread_watch(conn, board_uri, thread_id) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) ->
        ThreadWatcher.watch_state_for_board(token, board_uri)
        |> Map.get(thread_id, empty_thread_watch(thread_id))

      _ ->
        empty_thread_watch(thread_id)
    end
  end

  def moderator_body_class(conn, active_page, opts \\ []) do
    extra_classes =
      opts
      |> Keyword.get(:extra_classes, [])
      |> List.wrap()

    moderator_class =
      if conn.assigns[:current_moderator], do: "is-moderator", else: "is-not-moderator"

    ["8chan", "vichan", moderator_class | extra_classes ++ [active_page]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def primary_stylesheet(conn),
    do: conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"

  def data_stylesheet(conn) do
    conn
    |> primary_stylesheet()
    |> Path.basename()
  end

  def extra_stylesheets, do: @public_extra_stylesheets

  def public_shell_assigns(conn, active_page, opts \\ []) do
    %{
      watcher_count: watcher_count,
      watcher_unread_count: watcher_unread_count,
      watcher_you_count: watcher_you_count
    } = watcher_metrics(conn)

    head_meta_opts =
      [
        resource_version: conn.assigns[:asset_version],
        theme_label: conn.assigns[:theme_label],
        theme_options: conn.assigns[:theme_options],
        browser_timezone: conn.assigns[:browser_timezone],
        browser_timezone_offset_minutes: conn.assigns[:browser_timezone_offset_minutes],
        watcher_count: watcher_count,
        watcher_unread_count: watcher_unread_count,
        watcher_you_count: watcher_you_count
      ]
      |> Keyword.merge(Keyword.get(opts, :head_meta_opts, []))

    assigns = [
      public_shell: true,
      show_nav_arrows_page: Keyword.get(opts, :show_nav_arrows_page, true),
      viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
      base_stylesheet: "/stylesheets/style.css",
      body_data_stylesheet: data_stylesheet(conn),
      watcher_count: watcher_count,
      watcher_unread_count: watcher_unread_count,
      watcher_you_count: watcher_you_count,
      head_meta: PublicShell.head_meta(active_page, head_meta_opts),
      primary_stylesheet: primary_stylesheet(conn),
      primary_stylesheet_id: "stylesheet",
      extra_stylesheets: Keyword.get(opts, :extra_stylesheets, extra_stylesheets()),
      hide_theme_switcher: true,
      skip_app_stylesheet: true
    ]

    case Keyword.get(opts, :javascript_config) do
      nil ->
        Keyword.put(assigns, :javascript_urls, PublicShell.javascript_urls(active_page))

      config ->
        assigns
        |> Keyword.put(:eager_javascript_urls, PublicShell.eager_javascript_urls(active_page, config))
        |> Keyword.put(:javascript_urls, PublicShell.javascript_urls(active_page, config))
    end
  end

  defp own_post_ids_stamp(%MapSet{} = ids), do: :erlang.phash2(ids)
  defp own_post_ids_stamp(ids) when is_list(ids), do: ids |> Enum.sort() |> :erlang.phash2()
  defp own_post_ids_stamp(_ids), do: 0

  defp moderator_stamp(nil), do: nil
  defp moderator_stamp(moderator), do: {moderator.id, moderator.role}

  defp empty_thread_watch(thread_id) do
    %{watched: false, unread_count: 0, last_seen_post_id: thread_id}
  end
end
