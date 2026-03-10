defmodule EirinchanWeb.ReportManagementJSON do
  alias EirinchanWeb.{IpPresentation, PostView}

  def index(%{reports: reports, moderator: moderator}) do
    %{data: Enum.map(reports, &report_data(&1, moderator))}
  end

  defp report_data(report, moderator) do
    %{
      id: report.id,
      board_id: report.board_id,
      post_id: report.post_id,
      thread_id: report.thread_id,
      reason: report.reason,
      ip:
        if(PostView.can_view_ip?(moderator, report.board),
          do: IpPresentation.display_ip(report.ip, moderator),
          else: nil
        ),
      inserted_at: report.inserted_at,
      post_body: report.post && report.post.body
    }
  end
end
