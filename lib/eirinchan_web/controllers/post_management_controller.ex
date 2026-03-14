defmodule EirinchanWeb.PostManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Boards.{Board, BoardRecord}
  alias Eirinchan.Moderation
  alias Eirinchan.Posts
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.ModerationAudit

  action_fallback EirinchanWeb.FallbackController

  def show(conn, %{"uri" => uri, "post_id" => post_id}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, post} <- Posts.get_post(board, post_id) do
      render(conn, :show, post: post)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def update(conn, %{"uri" => uri, "post_id" => post_id} = params) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, post} <-
           Posts.update_post(
             board,
             post_id,
             Map.take(params, ["name", "email", "subject", "body"]),
             config: board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      ModerationAudit.log(conn, "Edited post No. #{post.id}", board: board)
      render(conn, :show, post: post)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete(conn, %{"uri" => uri, "post_id" => post_id}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, result} <-
           Posts.moderate_delete_post(board, post_id,
             config: board_config(board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      ModerationAudit.log(conn, "Deleted post No. #{post_id}", board: board)
      json(conn, %{data: result})
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete_file(conn, %{"uri" => uri, "post_id" => post_id} = params) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, post} <- delete_file_target(board, post_id, params, conn) do
      ModerationAudit.log(conn, "Deleted file from post No. #{post.id}", board: board)
      render(conn, :show, post: post)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def spoiler(conn, %{"uri" => uri, "post_id" => post_id} = params) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, post} <- spoiler_target(board, post_id, params, conn) do
      ModerationAudit.log(conn, "Spoilered file on post No. #{post.id}", board: board)
      render(conn, :show, post: post)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def move(
        conn,
        %{
          "uri" => uri,
          "post_id" => post_id,
          "target_board_uri" => target_uri,
          "target_thread_id" => target_thread_id
        }
      ) do
    with source_board when not is_nil(source_board) <- Boards.get_board_by_uri(uri),
         target_board when not is_nil(target_board) <- Boards.get_board_by_uri(target_uri),
         :ok <- authorize_board(conn, source_board),
         :ok <- authorize_board(conn, target_board),
         {:ok, post} <-
           Posts.move_reply(
             source_board,
             post_id,
             target_board,
             target_thread_id,
             source_config:
               board_config(source_board, EirinchanWeb.RequestMeta.request_host(conn)),
             target_config:
               board_config(target_board, EirinchanWeb.RequestMeta.request_host(conn))
           ) do
      ModerationAudit.log(
        conn,
        "Moved reply No. #{post.id} from /#{source_board.uri}/ to /#{target_board.uri}/ thread No. #{target_thread_id}",
        board: target_board
      )
      render(conn, :show, post: post)
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

  defp delete_file_target(board, post_id, params, conn) do
    config = board_config(board, EirinchanWeb.RequestMeta.request_host(conn))

    case Map.get(params, "file_index") do
      nil ->
        Posts.delete_post_files(board, post_id, config: config)

      file_index ->
        Posts.delete_post_file(board, post_id, file_index, config: config)
    end
  end

  defp spoiler_target(board, post_id, params, conn) do
    config = board_config(board, EirinchanWeb.RequestMeta.request_host(conn))

    case Map.get(params, "file_index") do
      nil ->
        Posts.spoilerize_post_files(board, post_id, config: config)

      file_index ->
        Posts.spoilerize_post_file(board, post_id, file_index, config: config)
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
