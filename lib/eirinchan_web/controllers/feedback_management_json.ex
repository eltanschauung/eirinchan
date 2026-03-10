defmodule EirinchanWeb.FeedbackManagementJSON do
  alias EirinchanWeb.{IpPresentation, PostView}

  def index(%{feedback: feedback, unread_count: unread_count, moderator: moderator}) do
    %{
      data: Enum.map(feedback, &feedback_data(&1, moderator)),
      unread_count: unread_count,
      actions: PostView.feedback_actions()
    }
  end

  def show(%{feedback: feedback, moderator: moderator}) do
    %{data: feedback_data(feedback, moderator), actions: PostView.feedback_actions()}
  end

  defp feedback_data(feedback, moderator) do
    %{
      id: feedback.id,
      name: feedback.name,
      email: feedback.email,
      body: feedback.body,
      ip_subnet:
        if(PostView.can_view_ip?(moderator),
          do: IpPresentation.display_ip(feedback.ip_subnet, moderator),
          else: nil
        ),
      read_at: feedback.read_at,
      comments: Enum.map(feedback.comments || [], &comment_data/1)
    }
  end

  defp comment_data(comment) do
    %{
      id: comment.id,
      body: comment.body,
      inserted_at: comment.inserted_at
    }
  end
end
