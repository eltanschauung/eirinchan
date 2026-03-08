defmodule EirinchanWeb.Plugs.LoadBoard do
  import Plug.Conn

  alias Eirinchan.Boards
  alias Eirinchan.Runtime

  def init(opts), do: opts

  def call(conn, _opts) do
    board_uri = conn.path_params["board"] || conn.params["board"]

    with true <- is_binary(board_uri),
         {:ok, runtime_context} <-
           Boards.open_board(board_uri,
             context:
               Runtime.bootstrap(request_host: EirinchanWeb.RequestMeta.request_host(conn)),
             request_host: EirinchanWeb.RequestMeta.request_host(conn)
           ) do
      conn
      |> assign(:runtime_context, runtime_context)
      |> assign(:current_board, Boards.get_board_by_uri!(runtime_context.board.uri))
      |> assign(:current_board_runtime, runtime_context.board)
      |> assign(:current_board_config, runtime_context.config)
    else
      _ ->
        conn
        |> send_resp(:not_found, "Board not found")
        |> halt()
    end
  end
end
