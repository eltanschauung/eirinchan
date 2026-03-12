defmodule EirinchanWeb.SearchController do
  use EirinchanWeb, :controller

  alias Eirinchan.Antispam
  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.CustomPages
  alias Eirinchan.Posts
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PublicShell
  alias EirinchanWeb.RequestMeta
  alias EirinchanWeb.ShowYous
  import Ecto.Query, only: [from: 2]

  plug :assign_search_shell

  def show(conn, params) do
    query = String.trim(params["q"] || params["search"] || "")
    board = board_from_param(params["board"])

    instance_overrides =
      Settings.current_instance_config()
      |> Config.deep_merge(Application.get_env(:eirinchan, :search_overrides, %{}))

    config = search_config(board, instance_overrides)
    boards = searchable_boards(instance_overrides)
    request = %{remote_ip: RequestMeta.effective_remote_ip(conn)}

    cond do
      not search_enabled?(config) ->
        render_search(conn, query, board, boards, [], "Search disabled.")

      board && not board_searchable?(board, config) ->
        render_search(conn, query, board, boards, [], "Search not available for this board.")

      query == "" ->
        render_search(conn, query, board, boards, [], nil)

      Antispam.search_rate_limited?(query, request, config, board_id: board && board.id) ->
        render_search(conn, query, board, boards, [], "Search rate limit exceeded.")

      true ->
        _ = Antispam.log_search_query(query, request, board_id: board && board.id)

        board_ids =
          if board do
            [board.id]
          else
            Enum.map(boards, & &1.id)
          end

        results =
          Posts.list_recent_posts(
            limit: 50,
            board_ids: board_ids,
            query: query
          )
          |> Repo.preload(:board)
          |> build_search_results()

        render_search(conn, query, board, boards, results, nil)
    end
  end

  defp render_search(conn, query, board, boards, results, error) do
    own_post_ids =
      results
      |> Enum.map(& &1.post)
      |> then(&ShowYous.owned_post_ids(conn, &1))

    render(conn, :show,
      query: query,
      board: board,
      boards: boards,
      global_message: current_global_message(),
      board_chrome: BoardChrome.for_board(%{uri: "bant"}),
      custom_pages: CustomPages.list_pages(),
      global_boardlist_groups: EirinchanWeb.PostView.boardlist_groups(boards),
      current_moderator: conn.assigns[:current_moderator],
      secure_manage_token: conn.assigns[:secure_manage_token],
      own_post_ids: own_post_ids,
      show_yous: ShowYous.enabled?(conn),
      results: results,
      result_count: length(results),
      grouped_results: group_search_results(results),
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
    |> assign(:body_class, "8chan vichan is-not-moderator active-search")
    |> assign(:body_data_stylesheet, Path.basename(stylesheet))
    |> assign(
      :head_html,
      PublicShell.head_html("search",
        resource_version: conn.assigns[:asset_version],
        theme_label: conn.assigns[:theme_label],
        theme_options: conn.assigns[:theme_options]
      )
    )
    |> assign(:javascript_urls, PublicShell.javascript_urls(:search))
    |> assign(:body_end_html, PublicShell.body_end_html())
    |> assign(:extra_stylesheets, [
      "/stylesheets/eirinchan-public.css",
      "/stylesheets/eirinchan-bant.css"
    ])
    |> assign(:skip_app_stylesheet, true)
    |> assign(:skip_flash_group, true)
  end

  defp current_global_message do
    case Settings.current_instance_config() |> Map.get(:global_message) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp board_from_param(nil), do: nil
  defp board_from_param(""), do: nil
  defp board_from_param(uri), do: Boards.get_board_by_uri(uri)

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

  defp group_search_results(results) do
    results
    |> Enum.group_by(& &1.board.id)
    |> Enum.map(fn {_board_id, board_results} ->
      first = hd(board_results)

      %{
        board: first.board,
        results: board_results
      }
    end)
    |> Enum.sort_by(& &1.board.uri)
  end

  defp result_url(%{board: board, thread_id: nil, id: id}),
    do: "/#{board.uri}/res/#{id}.html#p#{id}"

  defp result_url(%{board: board, thread_id: thread_id, id: id}),
    do: "/#{board.uri}/res/#{thread_id}.html#p#{id}"
end
