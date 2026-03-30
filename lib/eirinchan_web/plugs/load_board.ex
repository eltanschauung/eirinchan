defmodule EirinchanWeb.Plugs.LoadBoard do
  import Plug.Conn

  alias Eirinchan.Boards
  alias Eirinchan.Runtime
  alias EirinchanWeb.ErrorPages

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
      |> assign(
        :current_board_config,
        with_viewer_timezone(
          runtime_context.config,
          conn.assigns[:browser_timezone],
          conn.assigns[:browser_timezone_offset_minutes]
        )
      )
    else
      _ ->
        ErrorPages.not_found(conn)
    end
  end

  defp with_viewer_timezone(config, timezone, offset_minutes) do
    config
    |> maybe_put_viewer_timezone(timezone)
    |> maybe_put_viewer_offset(offset_minutes)
  end

  defp maybe_put_viewer_timezone(config, timezone) when is_binary(timezone), do: Map.put(config, :viewer_timezone, timezone)
  defp maybe_put_viewer_timezone(config, _timezone), do: config

  defp maybe_put_viewer_offset(config, offset_minutes) when is_integer(offset_minutes),
    do: Map.put(config, :viewer_timezone_offset_minutes, offset_minutes)

  defp maybe_put_viewer_offset(config, _offset_minutes), do: config
end
