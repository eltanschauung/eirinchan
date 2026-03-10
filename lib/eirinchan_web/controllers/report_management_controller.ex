defmodule EirinchanWeb.ReportManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Moderation
  alias Eirinchan.Reports

  action_fallback EirinchanWeb.FallbackController

  def index(conn, %{"uri" => uri}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board) do
      render(conn, :index, reports: Reports.list_reports(board))
    else
      nil -> {:error, :not_found}
    end
  end

  def delete(conn, %{"uri" => uri, "id" => id}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, _report} <- Reports.dismiss_report(board, id) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete_post(conn, %{"uri" => uri, "post_id" => post_id}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, _count} <- Reports.dismiss_reports_for_post(board, post_id) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def delete_ip(conn, %{"uri" => uri, "ip" => ip}) do
    with board when not is_nil(board) <- Boards.get_board_by_uri(uri),
         :ok <- authorize_board(conn, board),
         {:ok, _count} <- Reports.dismiss_reports_for_ip(board, ip) do
      send_resp(conn, :no_content, "")
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
end
