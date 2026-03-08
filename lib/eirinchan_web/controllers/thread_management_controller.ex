defmodule EirinchanWeb.ThreadManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Boards.{Board, BoardRecord}
  alias Eirinchan.Moderation
  alias Eirinchan.Posts
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings

  action_fallback EirinchanWeb.FallbackController

  def show(conn, %{"uri" => uri, "thread_id" => thread_id}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, [thread | _]} <- Posts.get_thread(board, thread_id) do
      render(conn, :show, thread: thread)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def update(conn, %{"uri" => uri, "thread_id" => thread_id} = params) do
    with board_record when not is_nil(board_record) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board_record),
         {:ok, thread} <-
           Posts.update_thread_state(
             board_record,
             thread_id,
             Map.take(params, ["sticky", "locked", "cycle", "sage"]),
             config: board_config(board_record, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      render(conn, :show, thread: thread)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def move(conn, %{"uri" => uri, "thread_id" => thread_id, "target_board_uri" => target_uri}) do
    with source_board when not is_nil(source_board) <- Boards.get_board_by_uri(uri),
         target_board when not is_nil(target_board) <- Boards.get_board_by_uri(target_uri),
         :ok <- authorize_board(conn, source_board),
         :ok <- authorize_board(conn, target_board),
         {:ok, thread} <-
           Posts.move_thread(
             source_board,
             thread_id,
             target_board,
             source_config:
               board_config(source_board, EirinchanWeb.RequestMeta.request_host(conn)),
             target_config:
               board_config(target_board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      render(conn, :show, thread: thread)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp authorize_board(conn, board) do
    if Moderation.board_access?(conn.assigns.current_moderator, board) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp board_config(%BoardRecord{} = board_record, request_host) do
    board =
      board_record
      |> BoardRecord.to_board()
      |> Board.with_runtime_paths(Config.compose(nil, Settings.current_instance_config(), %{}))

    Config.compose(nil, Settings.current_instance_config(), board_record.config_overrides,
      board: board,
      request_host: request_host
    )
  end
end
