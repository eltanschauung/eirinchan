defmodule EirinchanWeb.BoardController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Posts
  alias Eirinchan.ThreadWatcher
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PostView
  alias EirinchanWeb.PublicShell
  alias EirinchanWeb.ShowYous

  plug EirinchanWeb.Plugs.LoadBoard when action in [:show]
  plug EirinchanWeb.Plugs.LoadBoard when action in [:show_page]
  plug EirinchanWeb.Plugs.LoadBoard when action in [:catalog]
  plug EirinchanWeb.Plugs.LoadBoard when action in [:catalog_page]
  plug :require_catalog_theme when action in [:catalog]
  plug :require_catalog_theme when action in [:catalog_page]

  def show(conn, params) do
    render_page(conn, 1,
      fragment?: fragment_request?(params),
      fragment_md5?: fragment_md5_request?(params)
    )
  end

  def show_page(conn, %{"page_num_html" => page_num_html}) do
    page_num =
      page_num_html
      |> String.replace_suffix(".html", "")
      |> case do
        "index" ->
          1

        value ->
          case Integer.parse(value) do
            {parsed, ""} -> parsed
            _ -> nil
          end
      end

    if is_integer(page_num) and page_num > 0 do
      render_page(conn, page_num,
        fragment?: fragment_request?(conn.params),
        fragment_md5?: fragment_md5_request?(conn.params)
      )
    else
      send_resp(conn, :not_found, "Page not found")
    end
  end

  def catalog(conn, params) do
    render_catalog_page(conn, 1,
      fragment?: fragment_request?(params),
      fragment_md5?: fragment_md5_request?(params)
    )
  end

  def catalog_page(conn, %{"page_num_html" => page_num_html}) do
    page_num =
      page_num_html
      |> String.replace_suffix(".html", "")
      |> case do
        value ->
          case Integer.parse(value) do
            {parsed, ""} -> parsed
            _ -> nil
          end
      end

    if is_integer(page_num) and page_num > 1 do
      render_catalog_page(conn, page_num,
        fragment?: fragment_request?(conn.params),
        fragment_md5?: fragment_md5_request?(conn.params)
      )
    else
      send_resp(conn, :not_found, "Page not found")
    end
  end

  defp render_catalog_page(conn, page_num, opts \\ []) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    boards = Boards.list_boards()
    _ = Build.ensure_indexes(board, config: config)

    case Posts.list_catalog_page(board, page_num, config: config) do
      {:ok, page_data} ->
        chrome = BoardChrome.for_board(board)
        thread_watch_state = thread_watch_state(conn, board)
        %{watcher_count: watcher_count, watcher_you_count: watcher_you_count} =
          watcher_metrics(conn)
        own_post_ids = ShowYous.owned_post_ids(conn, Enum.map(page_data.threads, & &1.thread))
        show_yous = ShowYous.enabled?(conn)
        fragment? = Keyword.get(opts, :fragment?, false)
        fragment_md5? = Keyword.get(opts, :fragment_md5?, false)

        render_assigns = [
          layout: false,
          board: board,
          board_title: board.title,
          page_data: page_data,
          threads: page_data.threads,
          thread_watch_state: thread_watch_state,
          watcher_count: watcher_count,
          watcher_you_count: watcher_you_count,
          own_post_ids: own_post_ids,
          show_yous: show_yous,
          mobile_client?: conn.assigns[:mobile_client?] || false,
          current_moderator: conn.assigns[:current_moderator],
          secure_manage_token: conn.assigns[:secure_manage_token],
          config: config,
          boards: boards,
          board_chrome: chrome,
          global_boardlist_groups:
            BoardChrome.boardlist_groups(
              boards,
              chrome.boardlist_groups || PostView.boardlist_groups(boards)
            ),
          public_shell: true,
          viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
          base_stylesheet: "/stylesheets/style.css",
          body_class: catalog_body_class(conn),
          body_data_stylesheet: board_data_stylesheet(conn),
          page_title: "#{board.uri} - Catalog",
          head_html:
            PublicShell.head_html("catalog",
              board_name: board.uri,
              resource_version: conn.assigns[:asset_version],
              theme_label: conn.assigns[:theme_label],
              theme_options: conn.assigns[:theme_options],
              watcher_count: watcher_count,
              watcher_you_count: watcher_you_count
            ),
          eager_javascript_urls: PublicShell.eager_javascript_urls(:catalog, config),
          javascript_urls: PublicShell.javascript_urls(:catalog, config),
          body_end_html: PublicShell.body_end_html(),
          primary_stylesheet: board_primary_stylesheet(conn),
          primary_stylesheet_id: "stylesheet",
          extra_stylesheets: board_extra_stylesheets(board),
          hide_theme_switcher: true,
          skip_app_stylesheet: true
        ]

        fragment_md5 =
          render_fragment_md5(EirinchanWeb.BoardHTML, :catalog_fragment, render_assigns)

        if fragment_md5? do
          text(conn, fragment_md5)
        else

          conn = if fragment?, do: put_root_layout(conn, false), else: conn

          render(conn, if(fragment?, do: :catalog_fragment, else: :catalog),
            Keyword.put(render_assigns, :fragment_md5, fragment_md5)
          )
        end

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Page not found")
    end
  end

  defp render_page(conn, page, opts \\ []) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    boards = Boards.list_boards()
    _ = Build.ensure_indexes(board, config: config)

    case Posts.list_threads_page(board, page, config: config) do
      {:ok, page_data} ->
        chrome = BoardChrome.for_board(board)
        backlinks_map = page_backlinks_map(page_data)
        thread_watch_state = thread_watch_state(conn, board)
        %{watcher_count: watcher_count, watcher_you_count: watcher_you_count} =
          watcher_metrics(conn)
        own_post_ids = own_post_ids(conn, page_data)
        show_yous = ShowYous.enabled?(conn)
        fragment? = Keyword.get(opts, :fragment?, false)
        fragment_md5? = Keyword.get(opts, :fragment_md5?, false)

        render_assigns = [
          layout: false,
          board: board,
          board_title: board.title,
          page_title: "/#{board.uri}/ - #{board.title}",
          page_data: page_data,
          backlinks_map: backlinks_map,
          own_post_ids: own_post_ids,
          show_yous: show_yous,
          thread_watch_state: thread_watch_state,
          watcher_count: watcher_count,
          watcher_you_count: watcher_you_count,
          current_moderator: conn.assigns[:current_moderator],
          secure_manage_token: conn.assigns[:secure_manage_token],
          mobile_client?: conn.assigns[:mobile_client?] || false,
          config: config,
          boards: boards,
          board_chrome: chrome,
          global_boardlist_groups:
            BoardChrome.boardlist_groups(
              boards,
              chrome.boardlist_groups || PostView.boardlist_groups(boards)
            ),
          public_shell: true,
          viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
          base_stylesheet: "/stylesheets/style.css",
          body_class: board_body_class(conn),
          body_data_stylesheet: board_data_stylesheet(conn),
          head_html:
            PublicShell.head_html("index",
              board_name: board.uri,
              resource_version: conn.assigns[:asset_version],
              theme_label: conn.assigns[:theme_label],
              theme_options: conn.assigns[:theme_options],
              watcher_count: watcher_count,
              watcher_you_count: watcher_you_count
            ),
          eager_javascript_urls: PublicShell.eager_javascript_urls(:index, config),
          javascript_urls: PublicShell.javascript_urls(:index, config),
          body_end_html: PublicShell.body_end_html(),
          primary_stylesheet: board_primary_stylesheet(conn),
          primary_stylesheet_id: "stylesheet",
          extra_stylesheets: board_extra_stylesheets(board),
          hide_theme_switcher: true,
          skip_app_stylesheet: true
        ]

        fragment_md5 =
          render_fragment_md5(EirinchanWeb.BoardHTML, :index_fragment, render_assigns)

        if fragment_md5? do
          text(conn, fragment_md5)
        else

          conn = if fragment?, do: put_root_layout(conn, false), else: conn

          render(conn, if(fragment?, do: :index_fragment, else: :show),
            Keyword.put(render_assigns, :fragment_md5, fragment_md5)
          )
        end

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Page not found")
    end
  end

  defp page_backlinks_map(page_data) do
    posts =
      page_data.threads
      |> Enum.flat_map(fn summary -> [summary.thread | summary.replies] end)

    Posts.backlinks_map_for_posts(posts)
  end

  defp board_body_class(conn) do
    moderator_class =
      if conn.assigns[:current_moderator], do: "is-moderator", else: "is-not-moderator"

    "8chan vichan #{moderator_class} active-index"
  end

  defp catalog_body_class(conn) do
    moderator_class =
      if conn.assigns[:current_moderator], do: "is-moderator", else: "is-not-moderator"

    "8chan vichan #{moderator_class} theme-catalog active-catalog"
  end

  defp board_data_stylesheet(conn) do
    board_primary_stylesheet(conn)
    |> Path.basename()
  end

  defp board_primary_stylesheet(conn),
    do: conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"

  defp board_extra_stylesheets(_board),
    do: ["/stylesheets/eirinchan-public.css", "/stylesheets/eirinchan-bant.css"]

  defp fragment_request?(%{"fragment" => value}) when value in ["1", "true", "yes"], do: true
  defp fragment_request?(_params), do: false

  defp fragment_md5_request?(%{"fragment" => "md5"}), do: true
  defp fragment_md5_request?(_params), do: false

  defp render_fragment_md5(view, template, assigns),
    do: EirinchanWeb.FragmentHash.md5(view, template, assigns)

  defp require_catalog_theme(conn, _opts) do
    EirinchanWeb.Plugs.RequirePageTheme.call(conn, theme: "catalog")
  end

  defp thread_watch_state(conn, board) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) -> ThreadWatcher.watch_state_for_board(token, board.uri)
      _ -> %{}
    end
  end

  defp watcher_count(conn) do
    watcher_metrics(conn).watcher_count
  end

  defp watcher_metrics(conn) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) -> ThreadWatcher.watch_metrics(token)
      _ -> %{watcher_count: 0, watcher_you_count: 0}
    end
  end

  defp own_post_ids(conn, page_data) do
    posts =
      page_data.threads
      |> Enum.flat_map(fn summary -> [summary.thread | summary.replies] end)

    ShowYous.owned_post_ids(conn, posts)
  end
end
