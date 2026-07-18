defmodule EirinchanWeb.SearchController do
  use EirinchanWeb, :controller
  alias Eirinchan.Antispam
  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.EventLog
  alias Eirinchan.Posts
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias Eirinchan.Statistics
  alias EirinchanWeb.BrowserEntries
  alias EirinchanWeb.PublicShell
  alias EirinchanWeb.RequestMeta

  plug :assign_search_shell

  def show(conn, params) do
    query = String.trim(params["search"] || params["q"] || "")

    instance_overrides =
      Settings.current_instance_config()
      |> Config.deep_merge(Application.get_env(:eirinchan, :search_overrides, %{}))

    boards = searchable_boards(instance_overrides)
    board = board_from_param(params["board"], boards)
    config = search_config(board, instance_overrides)
    request = RequestMeta.public_identity(conn)

    cond do
      not search_enabled?(config) ->
        render_search(conn, query, board, boards, [], "Post search is disabled", config)

      query == "" or is_nil(board) ->
        render_search(conn, query, board, boards, [], nil, config)

      true ->
        case Antispam.reserve_configured_public_activity("search", request, config,
               board_id: board.id
             ) do
          {:ok, _entry} ->
            run_bounded_search(conn, query, board, boards, config, instance_overrides)

          {:error, _reason} ->
            EventLog.log(conn, "search.rejected", %{
              board: board.uri,
              outcome: "rate_limited",
              query_length: String.length(query)
            })

            render_search(
              Statistics.mark_rate_limited(conn, :search),
              query,
              board,
              boards,
              [],
              "Wait a while before searching again, please.",
              config
            )
        end
    end
  end

  defp run_bounded_search(conn, query, board, boards, config, instance_overrides) do
    if String.length(query) > search_max_query_length(config) do
      EventLog.log(conn, "search.rejected", %{
        board: board.uri,
        outcome: "query_too_long",
        query_length: String.length(query)
      })

      render_search(
        conn,
        query,
        board,
        boards,
        [],
        "Search queries are limited to #{search_max_query_length(config)} characters.",
        config
      )
    else
      run_search(conn, query, board, boards, config, instance_overrides)
    end
  end

  defp run_search(conn, query, board, boards, config, instance_overrides) do
    case Posts.search_posts(board, query,
           limit: search_limit(config),
           max_terms: search_max_terms(config)
         ) do
      {:query_too_broad, _posts} ->
        render_search(conn, query, board, boards, [], "Query too broad.", config)

      {:query_too_complex, _posts} ->
        render_search(
          conn,
          query,
          board,
          boards,
          [],
          "Search queries are limited to #{search_max_terms(config)} terms.",
          config
        )

      {:ok, posts} ->
        results =
          posts
          |> BrowserEntries.post_entries(boards, conn, instance_config: instance_overrides)

        render_search(conn, query, board, boards, results, nil, config)
    end
  end

  defp render_search(conn, query, board, boards, results, error, config) do
    render(conn, :show,
      query: query,
      board: board,
      boards: boards,
      global_boardlist_groups:
        EirinchanWeb.PostView.boardlist_groups(
          boards,
          mobile_client?: conn.assigns[:mobile_client?] || false
        ),
      results: results,
      result_count: length(results),
      config: config,
      board_chrome: EirinchanWeb.BoardChrome.default(config),
      error: error
    )
  end

  defp assign_search_shell(conn, _opts) do
    stylesheet = conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"

    conn
    |> assign(:page_title, "Search")
    |> assign(:public_shell, true)
    |> assign(:base_stylesheet, "/stylesheets/style.css")
    |> assign(:primary_stylesheet, stylesheet)
    |> assign(:primary_stylesheet_id, "stylesheet")
    |> assign(:body_class, "8chan vichan is-not-moderator active-page")
    |> assign(:body_data_stylesheet, Path.basename(stylesheet))
    |> assign(:watcher_count, 0)
    |> assign(:watcher_unread_count, 0)
    |> assign(:watcher_you_count, 0)
    |> assign(
      :head_meta,
      PublicShell.head_meta("page",
        resource_version: conn.assigns[:asset_version],
        theme_label: conn.assigns[:theme_label],
        theme_options: conn.assigns[:theme_options],
        browser_timezone: conn.assigns[:browser_timezone],
        browser_timezone_offset_minutes: conn.assigns[:browser_timezone_offset_minutes]
      )
    )
    |> assign(:javascript_urls, PublicShell.javascript_urls(:search))
    |> assign(:extra_stylesheets, [])
    |> assign(:skip_app_stylesheet, true)
    |> assign(:skip_flash_group, true)
    |> assign(:hide_theme_switcher, true)
  end

  defp board_from_param(nil, _boards), do: nil
  defp board_from_param("", _boards), do: nil
  defp board_from_param("none", _boards), do: nil

  defp board_from_param(uri, boards) do
    uri = String.trim(to_string(uri), "/")

    Enum.find(boards, &(&1.uri == uri))
  end

  defp search_config(nil, instance_overrides), do: Config.compose(nil, instance_overrides, %{})

  defp search_config(board_record, instance_overrides) do
    board = Eirinchan.Boards.BoardRecord.to_board(board_record)
    Config.compose(nil, instance_overrides, board.config_overrides || %{}, board: board)
  end

  defp searchable_boards(instance_overrides) do
    Boards.list_boards()
    |> Enum.filter(fn board ->
      board_searchable?(board, search_config(board, instance_overrides))
    end)
  end

  defp board_searchable?(%BoardRecord{} = board, config) do
    search_enabled?(config) and allowed_board?(board.uri, config)
  end

  defp search_enabled?(config), do: Map.get(config, :search_enabled, true)

  defp allowed_board?(uri, config) do
    allowed = normalize_uri_list(Map.get(config, :search_allowed_boards))
    disallowed = normalize_uri_list(Map.get(config, :search_disallowed_boards, []))

    (allowed == nil or uri in allowed) and uri not in disallowed
  end

  defp normalize_uri_list(nil), do: nil

  defp normalize_uri_list(values) when is_list(values) do
    Enum.map(values, &normalize_uri/1)
  end

  defp normalize_uri_list(value), do: [normalize_uri(value)]

  defp normalize_uri(uri) when is_binary(uri), do: uri |> String.trim() |> String.trim("/")
  defp normalize_uri(uri), do: to_string(uri)

  defp search_limit(config),
    do: Config.positive_integer(Map.get(config, :search_limit), 100)

  defp search_max_query_length(config),
    do: Config.positive_integer(Map.get(config, :search_max_query_length), 256)

  defp search_max_terms(config),
    do: Config.positive_integer(Map.get(config, :search_max_terms), 12)
end
