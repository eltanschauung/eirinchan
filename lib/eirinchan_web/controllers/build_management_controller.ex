defmodule EirinchanWeb.BuildManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Moderation
  alias EirinchanWeb.BoardRuntime

  action_fallback EirinchanWeb.FallbackController

  def create(conn, %{"uri" => uri}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board) do
      config = board_config(board, conn)

      result =
        case config.generation_strategy do
          "defer" -> Build.process_pending(board: board, config: config)
          _ -> Build.rebuild_board(board, config: config)
        end

      json(conn, %{
        data:
          Map.merge(
            %{board_id: board.id, strategy: config.generation_strategy},
            normalize_result(result)
          )
      })
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp normalize_result(%{processed: processed}), do: %{processed: processed}
  defp normalize_result(:ok), do: %{processed: 0}
  defp normalize_result(_), do: %{processed: 0}

  defp authorize_board(conn, board) do
    if Moderation.board_access?(conn.assigns.current_moderator, board) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp board_config(board_record, conn) do
    BoardRuntime.board_config(board_record, conn)
  end
end
