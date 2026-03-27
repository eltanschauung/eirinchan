defmodule EirinchanWeb.BoardController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Posts
  alias EirinchanWeb.Announcements
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PublicControllerHelpers
  alias EirinchanWeb.ShowYous

  plug EirinchanWeb.Plugs.RenderOverboard when action in [:show, :show_page]
  plug EirinchanWeb.Plugs.LoadBoard when action in [:show]
  plug EirinchanWeb.Plugs.LoadBoard when action in [:show_page]
  plug EirinchanWeb.Plugs.LoadBoard when action in [:catalog]
  plug EirinchanWeb.Plugs.LoadBoard when action in [:catalog_page]
  plug :require_catalog_theme when action in [:catalog]
  plug :require_catalog_theme when action in [:catalog_page]

  def show(conn, params) do
    render_page(conn, 1, PublicControllerHelpers.fragment_options(params))
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
      render_page(conn, page_num, PublicControllerHelpers.fragment_options(conn.params))
    else
      send_resp(conn, :not_found, "Page not found")
    end
  end

  def catalog(conn, params) do
    render_catalog_page(
      conn,
      1,
      Keyword.put(PublicControllerHelpers.fragment_options(params), :params, params)
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
      render_catalog_page(
        conn,
        page_num,
        Keyword.put(PublicControllerHelpers.fragment_options(conn.params), :params, conn.params)
      )
    else
      send_resp(conn, :not_found, "Page not found")
    end
  end

  defp render_catalog_page(conn, page_num, opts) do
    started_at = System.monotonic_time(:microsecond)
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    boards = Boards.list_boards()
    params = Keyword.get(opts, :params, %{})
    catalog_sort_by = normalize_catalog_sort(Map.get(params, "sort_by"))
    catalog_search_term = normalize_catalog_search(Map.get(params, "search"))
    _ = Build.ensure_indexes(board, config: config)

    case Posts.list_catalog_page(board, page_num,
           config: config,
           sort_by: catalog_sort_by,
           search: catalog_search_term
         ) do
      {:ok, page_data} ->
        page_data =
          Map.put(
            page_data,
            :pages,
            build_catalog_pages(board, page_data.total_pages, config, catalog_sort_by, catalog_search_term)
          )

        chrome = BoardChrome.for_board(board)
        thread_watch_state = PublicControllerHelpers.thread_watch_state(conn, board.uri)

        %{
          watcher_count: watcher_count,
          watcher_unread_count: watcher_unread_count,
          watcher_you_count: watcher_you_count
        } =
          PublicControllerHelpers.watcher_metrics(conn)

        own_post_ids = ShowYous.owned_post_ids(conn, Enum.map(page_data.threads, & &1.thread))
        show_yous = ShowYous.enabled?(conn)
        fragment? = Keyword.get(opts, :fragment?, false)
        fragment_md5? = Keyword.get(opts, :fragment_md5?, false)

        render_assigns = [
          layout: false,
          board: board,
          board_title: board.title,
          page_data: page_data,
          catalog_base_path: Eirinchan.ThreadPaths.catalog_page_path(board, 1, config),
          catalog_sort_by: catalog_sort_by,
          catalog_search_term: catalog_search_term,
          threads: page_data.threads,
          thread_watch_state: thread_watch_state,
          watcher_count: watcher_count,
          watcher_unread_count: watcher_unread_count,
          watcher_you_count: watcher_you_count,
          own_post_ids: own_post_ids,
          show_yous: show_yous,
          mobile_client?: conn.assigns[:mobile_client?] || false,
          current_moderator: conn.assigns[:current_moderator],
          secure_manage_token: conn.assigns[:secure_manage_token],
          config: config,
          news_blotter_html: Announcements.news_blotter_html(config),
          global_message_html:
            Announcements.global_message_html(config, surround_hr: true, board: board),
          boards: boards,
          board_chrome: chrome,
          global_boardlist_groups:
            BoardChrome.boardlist_groups(
              boards,
              chrome.boardlist_groups
            ),
          body_class:
            PublicControllerHelpers.moderator_body_class(conn, "active-catalog",
              extra_classes: ["theme-catalog"]
            ),
          page_title: "#{board.uri} - Catalog"
        ] ++
          PublicControllerHelpers.public_shell_assigns(conn, :catalog,
            javascript_config: config,
            head_meta_opts: [board_name: board.uri]
          )

        fragment_md5 =
          PublicControllerHelpers.render_fragment_md5(
            EirinchanWeb.BoardHTML,
            :catalog_fragment,
            render_assigns,
            fragment_cache_key(:catalog, board, page_data, render_assigns)
          )

        if fragment_md5? do
          text(conn, fragment_md5)
        else
          conn = if fragment?, do: put_root_layout(conn, false), else: conn

          conn =
            render(
              conn,
              if(fragment?, do: :catalog_fragment, else: :catalog),
              Keyword.put(render_assigns, :fragment_md5, fragment_md5)
            )

          PublicControllerHelpers.maybe_log_page_performance(
            "board.catalog",
            started_at,
            %{
              board: board.uri,
              page_num: page_num,
              fragment: fragment?,
              thread_count: length(page_data.threads),
              total_pages: page_data.total_pages
            },
            config
          )

          conn
        end

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Page not found")
    end
  end

  defp build_catalog_pages(board, total_pages, config, sort_by, search_term) do
    query =
      []
      |> maybe_put_catalog_query("sort_by", sort_by != "bump:desc", sort_by)
      |> maybe_put_catalog_query("search", search_term != "", search_term)
      |> URI.encode_query()

    Enum.map(1..total_pages, fn num ->
      base_link = Eirinchan.ThreadPaths.catalog_page_path(board, num, config)

      %{
        num: num,
        link: if(query == "", do: base_link, else: base_link <> "?" <> query)
      }
    end)
  end

  defp maybe_put_catalog_query(query, _key, false, _value), do: query
  defp maybe_put_catalog_query(query, _key, _condition, value) when value in [nil, ""], do: query
  defp maybe_put_catalog_query(query, key, _condition, value), do: [{key, value} | query]

  defp normalize_catalog_sort(value) when value in ["bump:desc", "time:desc", "reply:desc"],
    do: value

  defp normalize_catalog_sort(_value), do: "bump:desc"

  defp normalize_catalog_search(value) when is_binary(value), do: String.trim(value)
  defp normalize_catalog_search(_value), do: ""

  defp render_page(conn, page, opts) do
    started_at = System.monotonic_time(:microsecond)
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    boards = Boards.list_boards()
    _ = Build.ensure_indexes(board, config: config)

    case Posts.list_threads_page(board, page, config: config) do
      {:ok, page_data} ->
        chrome = BoardChrome.for_board(board)
        backlinks_map = page_backlinks_map(page_data)
        thread_watch_state = PublicControllerHelpers.thread_watch_state(conn, board.uri)

        %{
          watcher_count: watcher_count,
          watcher_unread_count: watcher_unread_count,
          watcher_you_count: watcher_you_count
        } =
          PublicControllerHelpers.watcher_metrics(conn)

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
          watcher_unread_count: watcher_unread_count,
          watcher_you_count: watcher_you_count,
          current_moderator: conn.assigns[:current_moderator],
          secure_manage_token: conn.assigns[:secure_manage_token],
          mobile_client?: conn.assigns[:mobile_client?] || false,
          config: config,
          news_blotter_html: Announcements.news_blotter_html(config),
          global_message_html:
            Announcements.global_message_html(config, surround_hr: true, board: board),
          boards: boards,
          board_chrome: chrome,
          global_boardlist_groups:
            BoardChrome.boardlist_groups(
              boards,
              chrome.boardlist_groups
            ),
          body_class: PublicControllerHelpers.moderator_body_class(conn, "active-index")
        ] ++
          PublicControllerHelpers.public_shell_assigns(conn, :index,
            javascript_config: config,
            head_meta_opts: [board_name: board.uri]
          )

        fragment_md5 =
          PublicControllerHelpers.render_fragment_md5(
            EirinchanWeb.BoardHTML,
            :index_fragment,
            render_assigns,
            fragment_cache_key(:index, board, page_data, render_assigns)
          )

        if fragment_md5? do
          text(conn, fragment_md5)
        else
          conn = if fragment?, do: put_root_layout(conn, false), else: conn

          conn =
            render(
              conn,
              if(fragment?, do: :index_fragment, else: :show),
              Keyword.put(render_assigns, :fragment_md5, fragment_md5)
            )

          PublicControllerHelpers.maybe_log_page_performance(
            "board.index",
            started_at,
            %{
              board: board.uri,
              page_num: page,
              fragment: fragment?,
              thread_count: length(page_data.threads),
              post_count:
                Enum.reduce(page_data.threads, 0, fn summary, acc ->
                  acc + 1 + length(summary.replies)
                end)
            },
            config
          )

          conn
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

  defp fragment_cache_key(kind, board, page_data, assigns) do
    {
      :board_fragment_md5,
      kind,
      board.id,
      Map.get(page_data, :page),
      page_data_stamp(page_data),
      PublicControllerHelpers.dynamic_fragment_stamp(assigns, :thread_watch_state)
    }
  end

  defp page_data_stamp(%{threads: threads}) do
    threads
    |> Enum.map(fn summary ->
      {summary.thread.id, summary.last_modified, length(summary.replies)}
    end)
    |> :erlang.phash2()
  end

  defp require_catalog_theme(conn, _opts) do
    EirinchanWeb.Plugs.RequirePageTheme.call(conn, theme: "catalog")
  end

  defp own_post_ids(conn, page_data) do
    posts =
      page_data.threads
      |> Enum.flat_map(fn summary -> [summary.thread | summary.replies] end)

    ShowYous.owned_post_ids(conn, posts)
  end
end
