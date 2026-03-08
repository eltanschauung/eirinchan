defmodule EirinchanWeb.BuildManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Build
  alias Eirinchan.Moderation
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings

  action_fallback EirinchanWeb.FallbackController

  def create(conn, %{"uri" => uri}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board) do
      config = board_config(board, EirinchanWeb.RequestMeta.request_host(conn))

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

  defp board_config(board_record, request_host) do
    Config.compose(
      nil,
      Settings.current_instance_config(),
      Config.normalize_override_keys(board_record.config_overrides || %{}),
      board: Eirinchan.Boards.BoardRecord.to_board(board_record),
      request_host: request_host
    )
  end
end
