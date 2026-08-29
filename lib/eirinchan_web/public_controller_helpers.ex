defmodule EirinchanWeb.PublicControllerHelpers do
  @moduledoc false

  alias Eirinchan.BrowserAbuse
  alias Eirinchan.LogSystem
  alias Eirinchan.PrimaryBoard
  alias Eirinchan.Settings
  alias Eirinchan.ThreadWatcher
  alias EirinchanWeb.FragmentHash
  alias EirinchanWeb.PublicShell
  alias EirinchanWeb.RequestMeta
  alias EirinchanWeb.UserFlagPreference

  import Plug.Conn, only: [get_req_header: 2, put_resp_header: 3, send_resp: 3]

  @empty_watcher_metrics %{watcher_count: 0, watcher_unread_count: 0, watcher_you_count: 0}
  @public_extra_stylesheets ["/stylesheets/eirinchan-public.css"]
  @default_slow_page_log_ms 2_000
  @fragment_cache_control "private, no-cache"

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

  def fragment_render_stamp(assigns, keys) when is_list(assigns) and is_list(keys) do
    keys
    |> Enum.map(&{&1, Keyword.get(assigns, &1)})
    |> FragmentHash.term_digest()
  end

  def fragment_not_modified?(conn, fragment_md5) when is_binary(fragment_md5) do
    expected = fragment_md5 |> fragment_etag() |> normalize_fragment_etag()

    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.any?(fn candidate ->
      candidate == "*" or normalize_fragment_etag(candidate) == expected
    end)
  end

  def fragment_not_modified?(_conn, _fragment_md5), do: false

  def send_fragment_not_modified(conn, fragment_md5) do
    conn
    |> put_resp_header("etag", fragment_etag(fragment_md5))
    |> put_resp_header("cache-control", @fragment_cache_control)
    |> send_resp(304, "")
  end

  def fragment_etag(fragment_md5), do: ~s("#{fragment_md5}")

  defp normalize_fragment_etag("W/" <> rest), do: String.trim(rest)
  defp normalize_fragment_etag(value), do: String.trim(value)

  def dynamic_fragment_stamp(assigns, watch_key) do
    {
      :erlang.phash2(Keyword.get(assigns, watch_key, %{})),
      moderator_stamp(Keyword.get(assigns, :current_moderator)),
      Keyword.get(assigns, :secure_manage_token),
      Keyword.get(assigns, :mobile_client?, false),
      Keyword.get(assigns, :browser_challenge_required?, false)
    }
  end

  def watcher_snapshot(conn, opts \\ []) do
    case conn.assigns[:browser_ref] do
      browser_ref when is_binary(browser_ref) -> ThreadWatcher.snapshot(browser_ref, opts)
      _ -> ThreadWatcher.empty_snapshot()
    end
  end

  def watcher_metrics(%Plug.Conn{} = conn), do: conn |> watcher_snapshot() |> watcher_metrics()
  def watcher_metrics(%{metrics: metrics}) when is_map(metrics), do: metrics
  def watcher_metrics(_snapshot), do: @empty_watcher_metrics

  def browser_challenge_required?(conn, config) do
    BrowserAbuse.challenge_required?(RequestMeta.public_identity(conn), config)
  end

  def thread_watch_state(%Plug.Conn{} = conn, board_uri) do
    conn
    |> watcher_snapshot()
    |> thread_watch_state(board_uri)
  end

  def thread_watch_state(%{watch_state_by_board: state_by_board}, board_uri)
      when is_map(state_by_board) and is_binary(board_uri),
      do: Map.get(state_by_board, board_uri, %{})

  def thread_watch_state(_snapshot, _board_uri), do: %{}

  def thread_watch(source, board_uri, thread_id) do
    source
    |> thread_watch_state(board_uri)
    |> Map.get(thread_id, empty_thread_watch(thread_id))
  end

  def watcher_state_by_board(%{watch_state_by_board: state}) when is_map(state), do: state
  def watcher_state_by_board(_snapshot), do: %{}

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

  def maybe_log_page_performance(page, started_at_us, metadata, config \\ nil)
      when is_binary(page) and is_integer(started_at_us) and is_map(metadata) do
    total_ms = round((System.monotonic_time(:microsecond) - started_at_us) / 1000)

    slow_page_log_ms =
      Application.get_env(:eirinchan, :slow_page_log_ms, @default_slow_page_log_ms)

    if is_integer(slow_page_log_ms) and total_ms >= slow_page_log_ms do
      LogSystem.log(
        :info,
        "page.performance",
        "page.performance",
        Map.merge(metadata, %{page: page, total_ms: total_ms, log_format: "json"}),
        config || Settings.current_instance_config()
      )
    end

    :ok
  end

  def public_shell_assigns(conn, active_page, opts \\ []) do
    watcher_snapshot =
      case Keyword.fetch(opts, :watcher_snapshot) do
        {:ok, snapshot} -> snapshot
        :error -> watcher_snapshot(conn)
      end

    %{
      watcher_count: watcher_count,
      watcher_unread_count: watcher_unread_count,
      watcher_you_count: watcher_you_count
    } = watcher_metrics(watcher_snapshot)

    head_meta_opts =
      [
        resource_version: conn.assigns[:asset_version],
        theme_label: Keyword.get(opts, :theme_label, conn.assigns[:theme_label]),
        theme_options: Keyword.get(opts, :theme_options, conn.assigns[:theme_options]),
        browser_timezone: conn.assigns[:browser_timezone],
        browser_timezone_offset_minutes: conn.assigns[:browser_timezone_offset_minutes],
        watcher_count: watcher_count,
        watcher_unread_count: watcher_unread_count,
        watcher_you_count: watcher_you_count
      ]
      |> Keyword.merge(Keyword.get(opts, :head_meta_opts, []))

    javascript_config = Keyword.get(opts, :javascript_config)
    user_flag_config = Keyword.get(opts, :user_flag_config, javascript_config)

    head_meta_opts =
      if is_map(user_flag_config) do
        Keyword.put(head_meta_opts, :user_flag_config, user_flag_config)
      else
        head_meta_opts
      end

    browser_challenge_required? =
      if is_map(javascript_config) do
        browser_challenge_required?(conn, javascript_config)
      else
        false
      end

    assigns = [
      public_shell: true,
      show_nav_arrows_page: Keyword.get(opts, :show_nav_arrows_page, true),
      viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
      base_stylesheet: Keyword.get(opts, :base_stylesheet, "/stylesheets/style.css"),
      body_data_stylesheet: Keyword.get(opts, :body_data_stylesheet, data_stylesheet(conn)),
      watcher_count: watcher_count,
      watcher_unread_count: watcher_unread_count,
      watcher_you_count: watcher_you_count,
      browser_challenge_required?: browser_challenge_required?,
      user_flag_preference_enabled?:
        is_map(user_flag_config) and Map.get(user_flag_config, :user_flag, false),
      user_flag_value:
        if(is_map(user_flag_config),
          do: UserFlagPreference.value(conn, user_flag_config),
          else: nil
        ),
      head_meta: PublicShell.head_meta(active_page, head_meta_opts),
      primary_stylesheet: Keyword.get(opts, :primary_stylesheet, primary_stylesheet(conn)),
      primary_stylesheet_id: "stylesheet",
      auto_theme_light: conn.assigns[:auto_theme_light],
      auto_theme_dark: conn.assigns[:auto_theme_dark],
      extra_stylesheets: Keyword.get(opts, :extra_stylesheets, extra_stylesheets()),
      theme_label: Keyword.get(opts, :theme_label, conn.assigns[:theme_label]),
      theme_options: Keyword.get(opts, :theme_options, conn.assigns[:theme_options]),
      hide_theme_switcher: Keyword.get(opts, :hide_theme_switcher, true),
      show_options_shell: Keyword.get(opts, :show_options_shell, true),
      skip_app_stylesheet: true
    ]

    case javascript_config do
      nil ->
        Keyword.put(assigns, :javascript_urls, PublicShell.javascript_urls(active_page))

      config ->
        assigns
        |> Keyword.put(
          :eager_javascript_urls,
          PublicShell.eager_javascript_urls(active_page, config)
        )
        |> Keyword.put(:javascript_urls, PublicShell.javascript_urls(active_page, config))
    end
  end

  def public_page_assigns(conn, page_kind, active_page, opts \\ []) do
    boards = Keyword.get_lazy(opts, :boards, &Eirinchan.Boards.list_boards/0)
    instance_config = Settings.effective_instance_config()
    primary_board = PrimaryBoard.resolve(boards, instance_config)

    shell_opts =
      [extra_stylesheets: extra_stylesheets()]
      |> Keyword.merge(Keyword.take(opts, [:watcher_snapshot, :user_flag_config]))

    common_assigns = public_shell_assigns(conn, active_page, shell_opts)

    [
      boards: boards,
      primary_board: primary_board,
      show_public_page_banner: Map.get(instance_config, :show_public_page_banner, false),
      board_chrome: EirinchanWeb.BoardChrome.for_board(primary_board),
      global_message_html: maybe_global_message_html(boards, opts),
      custom_pages: Eirinchan.CustomPages.list_pages(),
      global_boardlist_groups:
        EirinchanWeb.PostView.boardlist_groups(
          boards,
          mobile_client?: conn.assigns[:mobile_client?] || false
        ),
      body_class: public_body_class(page_kind)
    ] ++ common_assigns
  end

  defp moderator_stamp(nil), do: nil
  defp moderator_stamp(moderator), do: {moderator.id, moderator.role}

  defp empty_thread_watch(thread_id) do
    %{watched: false, unread_count: 0, you_unread_count: 0, last_seen_post_id: thread_id}
  end

  defp current_global_message_html(boards) do
    board_ids = Enum.map(boards, & &1.id)

    EirinchanWeb.Announcements.global_message_html(
      Settings.current_instance_config(),
      surround_hr: true,
      board_ids: board_ids
    )
  end

  defp maybe_global_message_html(boards, opts) do
    if Keyword.get(opts, :include_global_message, true), do: current_global_message_html(boards)
  end

  defp public_body_class("active-catalog"),
    do: "8chan vichan is-not-moderator theme-catalog active-catalog"

  defp public_body_class(page_kind), do: "8chan vichan is-not-moderator #{page_kind}"
end
