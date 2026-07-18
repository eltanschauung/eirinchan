defmodule EirinchanWeb.ModDashboardController do
  use EirinchanWeb, :controller

  alias Eirinchan.Feedback
  alias Eirinchan.Moderation
  alias Eirinchan.Posts
  alias Eirinchan.Reports
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias EirinchanWeb.Param

  @max_recent_posts 100

  plug EirinchanWeb.Plugs.RequireModeratorPermission,
       [permission: :recent] when action in [:recent]

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
    config = Config.compose(nil, Settings.current_instance_config(), %{})
    maximum = positive_limit(config.moderation_recent_posts_max, @max_recent_posts, 500)
    default = positive_limit(config.moderation_recent_posts_default, 25, maximum)
    limit = Param.bounded_integer(Map.get(params, "limit"), default, max: maximum)

    posts = Posts.list_recent_posts(limit: limit, board_ids: board_ids)
    render(conn, :recent, posts: posts)
  end

  defp count_reports(%{role: "admin"}, _boards), do: length(Reports.list_reports())

  defp count_reports(_moderator, boards),
    do: Enum.reduce(boards, 0, &(&2 + length(Reports.list_reports(&1))))

  defp positive_limit(value, _default, maximum) when is_integer(value) and value > 0,
    do: min(value, maximum)

  defp positive_limit(_value, default, maximum), do: min(default, maximum)
end
