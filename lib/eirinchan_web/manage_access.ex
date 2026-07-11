defmodule EirinchanWeb.ManageAccess do
  @moduledoc false

  alias Eirinchan.Moderation

  def authorize_board(conn, board) do
    if Moderation.board_access?(conn.assigns.current_moderator, board) do
      :ok
    else
      {:error, :forbidden}
    end
  end
end
