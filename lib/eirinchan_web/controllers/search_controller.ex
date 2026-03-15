defmodule EirinchanWeb.SearchController do
  use EirinchanWeb, :controller

  alias Eirinchan.Antispam
  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.PublicShell
  alias EirinchanWeb.RequestMeta
  alias EirinchanWeb.ShowYous
  import Ecto.Query, only: [from: 2]

  plug :assign_search_shell

  def show(conn, params) do
    query = String.trim(params["search"] || params["q"] || "")

    instance_overrides =
      Settings.current_instance_config()
      |> Config.deep_merge(Application.get_env(:eirinchan, :search_overrides, %{}))

    boards = searchable_boards(instance_overrides)
    board = board_from_param(params["board"], boards)
    config = search_config(board, instance_overrides)
    request = %{remote_ip: RequestMeta.effective_remote_ip(conn)}

    cond do
      not search_enabled?(config) ->
        render_search(conn, query, board, boards, [], "Post search is disabled", config)

      query == "" or is_nil(board) ->
        render_search(conn, query, board, boards, [], nil, config)

      public_search_rate_limited?(request, config) ->
        render_search(conn, query, board, boards, [], "Wait a while before searching again, please.", config)

      true ->
        _ = Antispam.log_search_query(query, request, board_id: board.id)

        case Posts.search_posts(board, query, limit: search_limit(config)) do
          {:query_too_broad, _posts} ->
            render_search(conn, query, board, boards, [], "Query too broad.", config)

          {:ok, posts} ->
            results =
              posts
              |> Repo.preload(:board)
              |> build_search_results()

            render_search(conn, query, board, boards, results, nil, config)
        end
    end
  end

  defp render_search(conn, query, board, boards, results, error, config) do
    own_post_ids =
      results
      |> Enum.map(& &1.post)
      |> then(&ShowYous.owned_post_ids(conn, &1))

    render(conn, :show,
      query: query,
      board: board,
      boards: boards,
      global_boardlist_groups: EirinchanWeb.PostView.boardlist_groups(boards),
      current_moderator: conn.assigns[:current_moderator],
      secure_manage_token: conn.assigns[:secure_manage_token],
      own_post_ids: own_post_ids,
      show_yous: ShowYous.enabled?(conn),
      results: results,
      result_count: length(results),
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

  defp build_search_results(posts) do
    thread_ids =
      posts
      |> Enum.map(&(&1.thread_id || &1.id))
      |> Enum.uniq()

    threads_by_id =
      Repo.all(from post in Post, where: post.id in ^thread_ids)
      |> Repo.preload(:board)
      |> Map.new(&{&1.id, &1})

    Enum.map(posts, fn post ->
      thread = Map.get(threads_by_id, post.thread_id || post.id, post)

      %{
        post: post,
        thread: thread,
        board: post.board,
        result_url: result_url(post)
      }
    end)
  end

  defp result_url(%{board: board, thread_id: nil} = post),
    do: "/#{board.uri}/res/#{PublicIds.public_id(post)}.html#p#{PublicIds.public_id(post)}"

  defp result_url(%{board: board, thread_id: _thread_id} = post),
    do:
      "/#{board.uri}/res/#{PublicIds.thread_public_id(post)}.html#p#{PublicIds.public_id(post)}"

  defp search_limit(config), do: max(Map.get(config, :search_limit, 100), 1)

  defp public_search_rate_limited?(request, config) do
    {per_ip_count, per_ip_minutes} = search_limit_tuple(config, :search_queries_per_minutes, 15, 2)
    {global_count, global_minutes} = search_limit_tuple(config, :search_queries_per_minutes_all, 50, 2)

    Antispam.public_search_rate_limited?(
      request,
      per_ip_count: per_ip_count,
      per_ip_window_seconds: per_ip_minutes * 60,
      global_count: global_count,
      global_window_seconds: global_minutes * 60
    )
  end

  defp search_limit_tuple(config, key, default_count, default_minutes) do
    case Map.get(config, key) do
      [count, minutes] when is_integer(count) and is_integer(minutes) -> {count, minutes}
      {count, minutes} when is_integer(count) and is_integer(minutes) -> {count, minutes}
      _ -> {default_count, default_minutes}
    end
  end
end
