defmodule EirinchanWeb.ThreadController do
  use EirinchanWeb, :controller

  alias Eirinchan.Announcement
  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Posts
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PublicShell

  plug EirinchanWeb.Plugs.LoadBoard

  def show(conn, %{"thread_id" => thread_id}) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    {normalized_thread_id, noko50?} = parse_thread_request(thread_id)
    _ = Build.ensure_thread(board, normalized_thread_id, config: config)

    case Posts.get_thread_view(board, normalized_thread_id, config: config, last_posts: noko50?) do
      {:ok, summary} ->
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

          render(conn, :show,
            layout: false,
            board: board,
            board_title: board.title,
            page_title:
              "/#{board.uri}/ - #{summary.thread.subject || summary.thread.body || summary.thread.id}",
            announcement: Announcement.current(),
            summary: summary,
            config: config,
            page_num: page_num,
            boards: Boards.list_boards(),
            board_chrome: BoardChrome.for_board(board),
            public_shell: true,
            viewport_content: "width=device-width, initial-scale=1, user-scalable=yes",
            base_stylesheet: "/stylesheets/style.css",
            body_class: board_body_class(conn),
            body_data_stylesheet: board_data_stylesheet(conn),
            head_html:
              PublicShell.head_html("thread",
                board_name: board.uri,
                thread_id: summary.thread.id,
                theme_label: conn.assigns[:theme_label],
                theme_options: conn.assigns[:theme_options]
              ),
            head_after_assets_html: PublicShell.thread_meta_html(board, summary.thread, config),
            javascript_urls: PublicShell.javascript_urls(:thread),
            body_end_html: PublicShell.body_end_html(),
            primary_stylesheet: board_primary_stylesheet(conn),
            primary_stylesheet_id: "stylesheet",
            extra_stylesheets: board_extra_stylesheets(board),
            hide_theme_switcher: true,
            skip_app_stylesheet: true
          )
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
end
