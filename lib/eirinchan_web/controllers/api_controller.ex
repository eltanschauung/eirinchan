defmodule EirinchanWeb.ApiController do
  use EirinchanWeb, :controller

  alias Eirinchan.Api
  alias Eirinchan.Boards
  alias Eirinchan.Posts

  plug EirinchanWeb.Plugs.LoadBoard when action in [:page, :catalog, :threads, :thread]
  plug :require_catalog_theme when action in [:catalog, :threads]

  def boards(conn, _params) do
    json(conn, Api.boards_json(Boards.list_boards()))
  end

  def page(conn, %{"page_num" => page_num}) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config

    with {:ok, page_data} <-
           Posts.list_threads_page(board, String.to_integer(page_num) + 1, config: config) do
      json(conn, Api.page_json(page_data, config))
    else
      {:error, :not_found} -> send_resp(conn, :not_found, "Page not found")
    end
  end

  def catalog(conn, _params) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    {:ok, pages} = Posts.list_page_data(board, config: config)
    json(conn, Api.catalog_json(pages, config: config))
  end

  def threads(conn, _params) do
    board = conn.assigns.current_board
    config = conn.assigns.current_board_config
    {:ok, pages} = Posts.list_page_data(board, config: config)
    json(conn, Api.catalog_json(pages, threads_page: true, config: config))
  end

  def thread(conn, %{"thread_id" => thread_id}) do
    board = conn.assigns.current_board

    case Posts.get_thread_view(board, thread_id) do
      {:ok, summary} -> json(conn, Api.thread_json(summary, conn.assigns.current_board_config))
      {:error, :not_found} -> send_resp(conn, :not_found, "Thread not found")
    end
  end

  defp require_catalog_theme(conn, _opts) do
    EirinchanWeb.Plugs.RequirePageTheme.call(conn, theme: "catalog")
  end
end
