defmodule EirinchanWeb.ThreadController do
  use EirinchanWeb, :controller

  alias Eirinchan.Announcement
  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Posts
  alias Eirinchan.ThreadPaths
  alias EirinchanWeb.BoardChrome
  alias EirinchanWeb.PublicShell
  alias EirinchanWeb.RequestMeta

  plug EirinchanWeb.Plugs.LoadBoard

  def show(conn, %{"thread_id" => thread_id}) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    _ = Build.ensure_thread(board, parse_thread_id(thread_id), config: config)

    case Posts.get_thread_view(board, thread_id) do
      {:ok, summary} ->
        canonical_path = ThreadPaths.thread_path(board, summary.thread, config)

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
            javascript_urls: PublicShell.javascript_urls(:thread_live),
            body_end_html: PublicShell.body_end_html(),
            primary_stylesheet: board_primary_stylesheet(conn),
            primary_stylesheet_id: "stylesheet",
            extra_stylesheets: board_extra_stylesheets(board),
            hide_theme_switcher: true,
            skip_app_stylesheet: true,
            live_socket: true,
            thread_live_session: %{
              "board_uri" => board.uri,
              "thread_id" => summary.thread.id,
              "request_host" => RequestMeta.request_host(conn),
              "current_moderator_id" => conn.assigns[:current_moderator] && conn.assigns.current_moderator.id,
              "secure_manage_token" => conn.assigns[:secure_manage_token]
            }
          )
        end

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Thread not found")
    end
  end

  defp parse_thread_id(thread_id) when is_integer(thread_id), do: thread_id

  defp parse_thread_id(thread_id) when is_binary(thread_id) do
    thread_id
    |> String.replace_suffix(".html", "")
    |> String.split("-", parts: 2)
    |> hd()
    |> String.to_integer()
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
