defmodule EirinchanWeb.ThreadController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Posts
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.ThreadWatcher
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.Announcements
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PostView
  alias EirinchanWeb.PublicControllerHelpers
  alias EirinchanWeb.PublicShell
  alias EirinchanWeb.ShowYous

  plug EirinchanWeb.Plugs.LoadBoard

  def show(conn, %{"thread_id" => thread_id}) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    {normalized_thread_id, noko50?} = parse_thread_request(thread_id)

    case Posts.get_thread_view(board, normalized_thread_id, config: config, last_posts: noko50?) do
      {:ok, summary} ->
        _ = Build.ensure_thread(board, summary.thread.id, config: config)
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
            case Posts.find_thread_page(board, PublicIds.public_id(summary.thread), config: config) do
              {:ok, value} -> value
              {:error, :not_found} -> 1
            end

          backlinks_map = Posts.backlinks_map_for_posts([summary.thread | summary.replies])
          thread_watch =
            PublicControllerHelpers.thread_watch(conn, board.uri, PublicIds.public_id(summary.thread))
          _ = maybe_mark_thread_seen(conn, board, summary)

          %{
            watcher_count: watcher_count,
            watcher_unread_count: watcher_unread_count,
            watcher_you_count: watcher_you_count
          } =
            PublicControllerHelpers.watcher_metrics(conn)

          own_post_ids = ShowYous.owned_post_ids(conn, [summary.thread | summary.replies])
          show_yous = ShowYous.enabled?(conn)

          fragment? = PublicControllerHelpers.fragment_request?(conn.params)
          fragment_md5? = PublicControllerHelpers.fragment_md5_request?(conn.params)

          render_assigns = [
            layout: false,
            board: board,
            board_title: board.title,
            page_title:
              "/#{board.uri}/ - #{summary.thread.subject || summary.thread.body || PublicIds.public_id(summary.thread)}",
            summary: summary,
            backlinks_map: backlinks_map,
            own_post_ids: own_post_ids,
            show_yous: show_yous,
            thread_watch: thread_watch,
            watcher_count: watcher_count,
            watcher_unread_count: watcher_unread_count,
            watcher_you_count: watcher_you_count,
            mobile_client?: conn.assigns[:mobile_client?] || false,
            current_moderator: conn.assigns[:current_moderator],
            secure_manage_token: conn.assigns[:secure_manage_token],
            config: config,
            global_message_html:
              Announcements.global_message_html(config, surround_hr: true, board: board),
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
            body_class: PublicControllerHelpers.moderator_body_class(conn, "active-thread"),
            body_data_stylesheet: PublicControllerHelpers.data_stylesheet(conn),
            head_meta:
              PublicShell.head_meta("thread",
                board_name: board.uri,
                thread_id: PublicIds.public_id(summary.thread),
                resource_version: conn.assigns[:asset_version],
                theme_label: conn.assigns[:theme_label],
                theme_options: conn.assigns[:theme_options],
                browser_timezone: conn.assigns[:browser_timezone],
                browser_timezone_offset_minutes: conn.assigns[:browser_timezone_offset_minutes],
                watcher_count: watcher_count,
                watcher_unread_count: watcher_unread_count,
                watcher_you_count: watcher_you_count
              ),
            head_extra_meta_tags: PublicShell.thread_meta(board, summary.thread, config),
            eager_javascript_urls: PublicShell.eager_javascript_urls(:thread, config),
            javascript_urls: PublicShell.javascript_urls(:thread, config),
            primary_stylesheet: PublicControllerHelpers.primary_stylesheet(conn),
            primary_stylesheet_id: "stylesheet",
            extra_stylesheets: PublicControllerHelpers.extra_stylesheets(),
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
            PublicControllerHelpers.render_fragment_md5(
              EirinchanWeb.ThreadHTML,
              :thread_fragment,
              render_assigns,
              fragment_cache_key(board, summary, render_assigns)
            )

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

  defp fragment_cache_key(board, summary, assigns) do
    {
      :thread_fragment_md5,
      board.id,
      summary.thread.id,
      summary.last_modified,
      length(summary.replies),
      PublicControllerHelpers.dynamic_fragment_stamp(assigns, :thread_watch)
    }
  end

  defp maybe_mark_thread_seen(conn, board, summary) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) ->
        last_seen_post_id =
          [summary.thread | summary.replies]
          |> Enum.map(&PublicIds.public_id/1)
          |> Enum.max(fn -> PublicIds.public_id(summary.thread) end)

        ThreadWatcher.mark_seen(token, board.uri, summary.thread.id, public_post_internal_id(board, last_seen_post_id))

      _ ->
        :ok
    end
  end

  defp public_post_internal_id(board, public_post_id) do
    case Posts.get_post(board, public_post_id) do
      {:ok, post} -> post.id
      _ -> public_post_id
    end
  end
end
