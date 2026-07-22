defmodule EirinchanWeb.SearchController do
  use EirinchanWeb, :controller

  alias Eirinchan.Antispam
  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.EventLog
  alias Eirinchan.Posts.Search
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias Eirinchan.Statistics
  alias Eirinchan.Statistics.SearchTelemetry
  alias EirinchanWeb.BrowserEntries
  alias EirinchanWeb.PublicControllerHelpers
  alias EirinchanWeb.RequestMeta

  plug :assign_search_shell

  def show(conn, params) do
    instance_overrides =
      Settings.current_instance_config()
      |> Config.deep_merge(Application.get_env(:eirinchan, :search_overrides, %{}))

    boards = searchable_boards(instance_overrides)
    criteria = Search.normalize_criteria(params)
    selected_boards = selected_boards(params, boards)
    selected_board = List.first(selected_boards)

    config =
      if length(selected_boards) == 1,
        do: search_config(selected_board, instance_overrides),
        else: search_config(nil, instance_overrides)

    context = %{
      criteria: criteria,
      selected_boards: selected_boards,
      selected_board: selected_board,
      boards: boards,
      board_groups: search_board_groups(boards, instance_overrides),
      config: config,
      instance_overrides: instance_overrides,
      searched?: search_requested?(params)
    }

    cond do
      not search_enabled?(config) ->
        track_and_render(conn, context, empty_page(), "Post search is disabled", :disabled)

      not context.searched? ->
        render_search(conn, context, empty_page(), nil)

      selected_boards == [] ->
        track_and_render(
          conn,
          context,
          empty_page(),
          "Select at least one board to search.",
          :invalid_board
        )

      not Search.meaningful?(criteria) ->
        track_and_render(
          conn,
          context,
          empty_page(),
          "Enter a search term or filter.",
          :empty
        )

      criteria_length(criteria) > search_max_query_length(config) ->
        reject_too_long(conn, context)

      Search.term_count(criteria) > search_max_terms(config) ->
        track_and_render(
          conn,
          context,
          empty_page(),
          "Search queries are limited to #{search_max_terms(config)} terms.",
          :invalid_terms
        )

      true ->
        reserve_and_search(conn, context)
    end
  end

  defp reserve_and_search(conn, context) do
    request = RequestMeta.public_identity(conn)
    board_id = if length(context.selected_boards) == 1, do: context.selected_board.id

    case Antispam.reserve_configured_public_activity("search", request, context.config,
           board_id: board_id
         ) do
      {:ok, _entry} ->
        run_search(conn, context)

      {:error, _reason} ->
        EventLog.log(conn, "search.rejected", %{
          board_count: length(context.selected_boards),
          outcome: "rate_limited",
          query_length: criteria_length(context.criteria)
        })

        conn
        |> Statistics.mark_rate_limited(:search)
        |> track_and_render(
          context,
          empty_page(),
          "Wait a while before searching again, please.",
          :rate_limited
        )
    end
  end

  defp run_search(conn, context) do
    opts = [
      page: positive_param(conn.params["page"], 1),
      page_size: search_page_size(context.config),
      max_matches: search_max_matches(context.config),
      timeout: search_timeout_ms(context.config)
    ]

    case Search.run(context.selected_boards, context.criteria, opts) do
      {:ok, page} ->
        results =
          BrowserEntries.post_entries(page.posts, context.boards, conn,
            instance_config: context.instance_overrides
          )

        track_and_render(conn, context, Map.put(page, :results, results), nil, :results)

      {:error, :unavailable} ->
        EventLog.log(conn, "search.failed", %{
          board_count: length(context.selected_boards),
          outcome: "database_unavailable"
        })

        track_and_render(
          conn,
          context,
          empty_page(),
          "Search is temporarily unavailable. Try again shortly.",
          :unavailable
        )
    end
  end

  defp reject_too_long(conn, context) do
    EventLog.log(conn, "search.rejected", %{
      board_count: length(context.selected_boards),
      outcome: "query_too_long",
      query_length: criteria_length(context.criteria)
    })

    track_and_render(
      conn,
      context,
      empty_page(),
      "Search queries are limited to #{search_max_query_length(context.config)} characters.",
      :invalid_query
    )
  end

  defp track_and_render(conn, context, page, error, outcome) do
    if context.searched? do
      SearchTelemetry.record(conn, context.criteria, context.selected_boards, outcome,
        scope: conn.params["scope"],
        page: positive_param(conn.params["page"], 1),
        result_count: page.total,
        capped?: page.capped?
      )
    end

    render_search(conn, context, page, error)
  end

  defp render_search(conn, context, page, error) do
    selected_uris = Enum.map(context.selected_boards, & &1.uri)

    render(conn, :show,
      criteria: context.criteria,
      selected_board: context.selected_board,
      selected_boards: context.selected_boards,
      selected_uris: MapSet.new(selected_uris),
      boards: context.boards,
      board_groups: context.board_groups,
      global_boardlist_groups:
        EirinchanWeb.PostView.boardlist_groups(
          context.boards,
          mobile_client?: conn.assigns[:mobile_client?] || false
        ),
      results: Map.get(page, :results, []),
      result_count: page.total,
      result_capped?: page.capped?,
      page: page.page,
      total_pages: page.total_pages,
      config: context.config,
      board_chrome: EirinchanWeb.BoardChrome.default(context.config),
      error: error,
      searched?: context.searched?,
      search_params: pagination_params(conn.params, selected_uris)
    )
  end

  defp empty_page do
    %{posts: [], total: 0, capped?: false, page: 1, page_size: 25, total_pages: 1}
  end

  defp selected_boards(params, boards) do
    requested =
      cond do
        params["scope"] == "all" -> Enum.map(boards, & &1.uri)
        is_list(params["boards"]) -> params["boards"]
        is_binary(params["boards"]) -> [params["boards"]]
        is_binary(params["board"]) -> [params["board"]]
        true -> []
      end

    requested =
      requested
      |> Enum.map(&normalize_uri/1)
      |> MapSet.new()

    Enum.filter(boards, &MapSet.member?(requested, &1.uri))
  end

  defp search_board_groups(boards, instance_overrides) do
    archive_targets =
      boards
      |> Enum.map(fn board ->
        Map.get(search_config(board, instance_overrides), :archive_board)
      end)
      |> Enum.map(&normalize_uri/1)
      |> Enum.reject(&(&1 in ["", "none"]))
      |> MapSet.new()

    %{
      archives: Enum.filter(boards, &MapSet.member?(archive_targets, &1.uri)),
      boards: Enum.reject(boards, &MapSet.member?(archive_targets, &1.uri))
    }
  end

  defp search_requested?(params) do
    params["scope"] in ["selected", "all"] or
      Enum.any?(
        ~w(search q text thread tnum post_id subject username name tripcode email uid country filename image_hash imagehash width height start end),
        &present?(params[&1])
      )
  end

  defp criteria_length(criteria) do
    ~w(text thread post_id subject username tripcode email uid country filename image_hash)a
    |> Enum.map(&(Map.get(criteria, &1) || ""))
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.length/1)
    |> Enum.sum()
  end

  defp pagination_params(params, selected_uris) do
    params
    |> Map.take(
      ~w(text search q thread tnum post_id subject username name tripcode email uid country filename image_hash imagehash width height start end image type results order highlight scope theme_board)
    )
    |> Map.put("boards", selected_uris)
    |> Map.put("scope", "selected")
  end

  defp assign_search_shell(conn, _opts) do
    shell_assigns =
      PublicControllerHelpers.public_shell_assigns(conn, :search,
        extra_stylesheets:
          PublicControllerHelpers.extra_stylesheets() ++ ["/stylesheets/search.css"],
        head_meta_opts: [board_name: conn.assigns[:theme_board_uri]],
        show_nav_arrows_page: false
      )

    page_assigns = [
      page_title: "Search",
      body_class:
        PublicControllerHelpers.moderator_body_class(conn, "active-search",
          extra_classes: ["active-page"]
        ),
      skip_flash_group: true
    ]

    Enum.reduce(shell_assigns ++ page_assigns, conn, fn {key, value}, conn ->
      assign(conn, key, value)
    end)
  end

  defp search_config(nil, instance_overrides), do: Config.compose(nil, instance_overrides, %{})

  defp search_config(%BoardRecord{} = board_record, instance_overrides) do
    board = BoardRecord.to_board(board_record)
    Config.compose(nil, instance_overrides, board.config_overrides || %{}, board: board)
  end

  defp searchable_boards(instance_overrides) do
    Boards.list_boards()
    |> Enum.filter(fn board ->
      config = search_config(board, instance_overrides)
      search_enabled?(config) and allowed_board?(board.uri, config)
    end)
  end

  defp search_enabled?(config), do: Map.get(config, :search_enabled, true)

  defp allowed_board?(uri, config) do
    allowed = normalize_uri_list(Map.get(config, :search_allowed_boards))
    disallowed = normalize_uri_list(Map.get(config, :search_disallowed_boards, []))
    (allowed == nil or uri in allowed) and uri not in disallowed
  end

  defp normalize_uri_list(nil), do: nil
  defp normalize_uri_list(values) when is_list(values), do: Enum.map(values, &normalize_uri/1)
  defp normalize_uri_list(value), do: [normalize_uri(value)]
  defp normalize_uri(nil), do: ""
  defp normalize_uri(uri), do: uri |> to_string() |> String.trim() |> String.trim("/")
  defp present?(value), do: value not in [nil, "", []]

  defp positive_param(value, default) do
    case Integer.parse(to_string(value || "")) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp search_page_size(config),
    do: Config.positive_integer(Map.get(config, :search_page_size), 25)

  defp search_max_matches(config),
    do: Config.positive_integer(Map.get(config, :search_max_matches), 5_000)

  defp search_timeout_ms(config),
    do: Config.positive_integer(Map.get(config, :search_timeout_ms), 3_000)

  defp search_max_query_length(config),
    do: Config.positive_integer(Map.get(config, :search_max_query_length), 256)

  defp search_max_terms(config),
    do: Config.positive_integer(Map.get(config, :search_max_terms), 12)
end
