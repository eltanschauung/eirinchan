defmodule EirinchanWeb.BoardManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Moderation
  alias EirinchanWeb.ModerationAudit

  action_fallback EirinchanWeb.FallbackController

  def index(conn, _params) do
    render(conn, :index, boards: Moderation.list_accessible_boards(conn.assigns.current_moderator))
  end

  def create(conn, params) do
    with {:ok, board} <- Boards.create_board(params) do
      ModerationAudit.log(conn, "Created board /#{board.uri}/", board: board)
      conn
      |> put_status(:created)
      |> render(:show, board: board)
    end
  end

  def show(conn, %{"uri" => uri}) do
    case load_authorized_board(conn, uri) do
      {:ok, board} -> render(conn, :show, board: board)
      error -> error
    end
  end

  def update(conn, %{"uri" => uri} = params) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         {:ok, board} <- Boards.update_board(board, Map.delete(params, "uri")) do
      ModerationAudit.log(conn, "Updated board /#{board.uri}/", board: board)
      render(conn, :show, board: board)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete(conn, %{"uri" => uri}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         {:ok, _board} <- Boards.delete_board(board) do
      ModerationAudit.log(conn, "Deleted board /#{uri}/", board_uri: uri)
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp load_authorized_board(conn, uri) do
    case Boards.get_board_by_uri(uri) do
      nil ->
        {:error, :not_found}

      board ->
        if Moderation.board_access?(conn.assigns.current_moderator, board) do
          {:ok, board}
        else
          {:error, :forbidden}
        end
    end
  end
end
