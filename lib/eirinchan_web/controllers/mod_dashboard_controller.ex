defmodule EirinchanWeb.ModDashboardController do
  use EirinchanWeb, :controller

  alias Eirinchan.Feedback
  alias Eirinchan.Moderation
  alias Eirinchan.Posts
  alias Eirinchan.Reports
  alias EirinchanWeb.Param

  @max_recent_posts 100

  def show(conn, _params) do
    boards = Moderation.list_accessible_boards(conn.assigns.current_moderator)

    data = %{
      boards: Enum.map(boards, &%{id: &1.id, uri: &1.uri, title: &1.title}),
      board_count: length(boards),
      report_count: count_reports(conn.assigns.current_moderator, boards),
      feedback_unread_count: Feedback.unread_count()
    }

    render(conn, :show, data: data)
  end

  def recent(conn, params) do
    boards = Moderation.list_accessible_boards(conn.assigns.current_moderator)
    board_ids = Enum.map(boards, & &1.id)
    limit = Param.bounded_integer(Map.get(params, "limit"), 25, max: @max_recent_posts)

    posts = Posts.list_recent_posts(limit: limit, board_ids: board_ids)
    render(conn, :recent, posts: posts)
  end

  defp count_reports(%{role: "admin"}, _boards), do: length(Reports.list_reports())

  defp count_reports(_moderator, boards),
    do: Enum.reduce(boards, 0, &(&2 + length(Reports.list_reports(&1))))
end
