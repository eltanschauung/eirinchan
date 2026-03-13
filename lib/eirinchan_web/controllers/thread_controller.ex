defmodule EirinchanWeb.ThreadController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Posts
  alias Eirinchan.ThreadWatcher
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.Announcements
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PostView
  alias EirinchanWeb.PublicShell
  alias EirinchanWeb.ShowYous

  plug EirinchanWeb.Plugs.LoadBoard

  def show(conn, %{"thread_id" => thread_id}) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    {normalized_thread_id, noko50?} = parse_thread_request(thread_id)
    _ = Build.ensure_thread(board, normalized_thread_id, config: config)

    case Posts.get_thread_view(board, normalized_thread_id, config: config, last_posts: noko50?) do
      {:ok, summary} ->
        boards = Boards.list_boards()
        chrome = BoardChrome.for_board(board)

        canonical_path =
          if noko50? and summary.has_noko50 do
            ThreadPaths.thread_path(board, summary.thread, config, noko50: true)
          else
            ThreadPaths.thread_path(board, summary.thread, config)
          end

        if conn.request_path != canonical_path do
          redirect(conn, to: canonical_path)
        else
          page_num =
            case Posts.find_thread_page(board, summary.thread.id, config: config) do
              {:ok, value} -> value
              {:error, :not_found} -> 1
            end

          backlinks_map = Posts.backlinks_map_for_posts([summary.thread | summary.replies])
          thread_watch = thread_watch(conn, board, summary.thread.id)
          _ = maybe_mark_thread_seen(conn, board, summary)

          %{watcher_count: watcher_count, watcher_you_count: watcher_you_count} =
            watcher_metrics(conn)

          own_post_ids = ShowYous.owned_post_ids(conn, [summary.thread | summary.replies])
          show_yous = ShowYous.enabled?(conn)

          fragment? = fragment_request?(conn.params)
          fragment_md5? = fragment_md5_request?(conn.params)

          render_assigns = [
            layout: false,
            board: board,
            board_title: board.title,
            page_title:
              "/#{board.uri}/ - #{summary.thread.subject || summary.thread.body || summary.thread.id}",
            summary: summary,
            backlinks_map: backlinks_map,
            own_post_ids: own_post_ids,
            show_yous: show_yous,
            thread_watch: thread_watch,
            watcher_count: watcher_count,
            watcher_you_count: watcher_you_count,
            mobile_client?: conn.assigns[:mobile_client?] || false,
            current_moderator: conn.assigns[:current_moderator],
            secure_manage_token: conn.assigns[:secure_manage_token],
            config: config,
            global_message_html: Announcements.global_message_html(config, surround_hr: true),
            page_num: page_num,
            boards: boards,
            board_chrome: chrome,
            global_boardlist_groups:
              BoardChrome.boardlist_groups(
                boards,
                chrome.boardlist_groups || PostView.boardlist_groups(boards)
              ),
            public_shell: true,
            show_nav_arrows_page: true,
            viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
            base_stylesheet: "/stylesheets/style.css",
            body_class: board_body_class(conn),
            body_data_stylesheet: board_data_stylesheet(conn),
            head_html:
              PublicShell.head_html("thread",
                board_name: board.uri,
                thread_id: summary.thread.id,
                resource_version: conn.assigns[:asset_version],
                theme_label: conn.assigns[:theme_label],
                theme_options: conn.assigns[:theme_options],
                watcher_count: watcher_count,
                watcher_you_count: watcher_you_count
              ),
            head_after_assets_html: PublicShell.thread_meta_html(board, summary.thread, config),
            eager_javascript_urls: PublicShell.eager_javascript_urls(:thread, config),
            javascript_urls: PublicShell.javascript_urls(:thread, config),
            body_end_html: PublicShell.body_end_html(),
            primary_stylesheet: board_primary_stylesheet(conn),
            primary_stylesheet_id: "stylesheet",
            extra_stylesheets: board_extra_stylesheets(board),
            hide_theme_switcher: true,
            skip_app_stylesheet: true
          ]

          quick_reply_html =
            Phoenix.Template.render_to_string(
              EirinchanWeb.ThreadHTML,
              "quick_reply",
              "html",
              render_assigns
            )

          render_assigns = Keyword.put(render_assigns, :quick_reply_html, quick_reply_html)

          fragment_md5 =
            render_fragment_md5(EirinchanWeb.ThreadHTML, :thread_fragment, render_assigns)

          if fragment_md5? do
            text(conn, fragment_md5)
          else
            conn = if fragment?, do: put_root_layout(conn, false), else: conn

            render(
              conn,
              if(fragment?, do: :thread_fragment, else: :show),
              Keyword.put(render_assigns, :fragment_md5, fragment_md5)
            )
          end
        end

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Thread not found")
    end
  end

  defp parse_thread_request(thread_id) when is_integer(thread_id), do: {thread_id, false}

  defp parse_thread_request(thread_id) when is_binary(thread_id) do
    normalized =
      thread_id
      |> String.replace_suffix(".html", "")

    noko50? = String.contains?(normalized, "+50")

    id =
      normalized
      |> String.replace("+50", "")
      |> String.split("-", parts: 2)
      |> hd()
      |> String.to_integer()

    {id, noko50?}
  end

  defp fragment_request?(%{"fragment" => value}) when value in ["1", "true", "yes"], do: true
  defp fragment_request?(_params), do: false

  defp fragment_md5_request?(%{"fragment" => "md5"}), do: true
  defp fragment_md5_request?(_params), do: false

  defp render_fragment_md5(view, template, assigns),
    do: EirinchanWeb.FragmentHash.md5(view, template, assigns)

  defp board_body_class(conn) do
    moderator_class =
      if conn.assigns[:current_moderator], do: "is-moderator", else: "is-not-moderator"

    "8chan vichan #{moderator_class} active-thread"
  end

  defp board_data_stylesheet(conn) do
    board_primary_stylesheet(conn)
    |> Path.basename()
  end

  defp board_primary_stylesheet(conn),
    do: conn.assigns[:theme_stylesheet] || "/stylesheets/yotsuba.css"

  defp board_extra_stylesheets(_board),
    do: ["/stylesheets/eirinchan-public.css", "/stylesheets/eirinchan-bant.css"]

  defp thread_watch(conn, board, thread_id) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) ->
        ThreadWatcher.watch_state_for_board(token, board.uri)
        |> Map.get(thread_id, %{watched: false, unread_count: 0, last_seen_post_id: thread_id})

      _ ->
        %{watched: false, unread_count: 0, last_seen_post_id: thread_id}
    end
  end

  defp maybe_mark_thread_seen(conn, board, summary) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) ->
        last_seen_post_id =
          [summary.thread | summary.replies]
          |> Enum.map(& &1.id)
          |> Enum.max(fn -> summary.thread.id end)

        ThreadWatcher.mark_seen(token, board.uri, summary.thread.id, last_seen_post_id)

      _ ->
        :ok
    end
  end

  defp watcher_metrics(conn) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) -> ThreadWatcher.watch_metrics(token)
      _ -> %{watcher_count: 0, watcher_you_count: 0}
    end
  end
end
