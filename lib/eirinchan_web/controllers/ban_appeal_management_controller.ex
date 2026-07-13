defmodule EirinchanWeb.BanAppealManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Bans
  alias Eirinchan.Boards

  action_fallback EirinchanWeb.FallbackController

  plug EirinchanWeb.Plugs.RequireModeratorPermission,
       [permission: :view_ban_appeals] when action in [:index]

  def index(conn, %{"uri" => uri}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board) do
      render(conn, :index, appeals: Bans.list_appeals(board_id: board.id))
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def update(conn, %{"uri" => uri, "id" => id} = params) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         appeal when not is_nil(appeal) <- Bans.get_appeal(id),
         true <- appeal.ban && appeal.ban.board_id == board.id,
         {:ok, resolved_appeal} <-
           Bans.resolve_appeal(appeal.id, %{
             status: Map.get(params, "status", "resolved"),
             resolution_note: params["resolution_note"]
           }) do
      render(conn, :show, appeal: resolved_appeal)
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      error -> error
    end
  end

  defp authorize_board(conn, board), do: EirinchanWeb.ManageAccess.authorize_board(conn, board)
end
