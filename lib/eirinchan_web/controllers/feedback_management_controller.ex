defmodule EirinchanWeb.FeedbackManagementController do
  use EirinchanWeb, :controller

  alias Eirinchan.Feedback

  action_fallback EirinchanWeb.FallbackController

  def index(conn, _params) do
    render(conn, :index,
      feedback: Feedback.list_feedback(),
      unread_count: Feedback.unread_count(),
      moderator: conn.assigns.current_moderator
    )
  end

  def mark_read(conn, %{"id" => id}) do
    with {:ok, _feedback} <- Feedback.mark_read(id),
         feedback when not is_nil(feedback) <- Feedback.get_feedback(id) do
      render(conn, :show, feedback: feedback, moderator: conn.assigns.current_moderator)
    else
      nil -> {:error, :not_found}
    end
  end

  def create_comment(conn, %{"id" => id} = params) do
    with {:ok, _comment} <- Feedback.add_comment(id, params),
         {:ok, _feedback} <- Feedback.mark_read(id),
         feedback when not is_nil(feedback) <- Feedback.get_feedback(id) do
      render(conn, :show, feedback: feedback, moderator: conn.assigns.current_moderator)
    else
      nil -> {:error, :not_found}
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _feedback} <- Feedback.delete_feedback(id) do
      send_resp(conn, :no_content, "")
    end
  end
end
