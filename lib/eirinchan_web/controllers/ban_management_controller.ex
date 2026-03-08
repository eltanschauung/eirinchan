defmodule EirinchanWeb.BanManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Bans
  alias Eirinchan.Boards
  alias Eirinchan.Moderation

  action_fallback EirinchanWeb.FallbackController

  def index(conn, %{"uri" => uri}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board) do
      render(conn, :index, bans: Bans.list_bans(board_id: board.id))
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def create(conn, %{"uri" => uri} = params) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, ban} <-
           Bans.create_ban(%{
             board_id: board.id,
             mod_user_id: conn.assigns.current_moderator.id,
             ip_subnet: params["ip_subnet"],
             reason: params["reason"],
             expires_at: params["expires_at"],
             length: params["length"],
             active: Map.get(params, "active", true)
           }) do
      conn
      |> put_status(:created)
      |> render(:show, ban: ban)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def update(conn, %{"uri" => uri, "id" => id} = params) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         %{} = ban <- Bans.get_ban(id),
         true <- ban.board_id == board.id,
         {:ok, ban} <-
           Bans.update_ban(
             ban,
             Map.take(params, ["ip_subnet", "reason", "expires_at", "length", "active"])
           ) do
      render(conn, :show, ban: ban)
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
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
end
