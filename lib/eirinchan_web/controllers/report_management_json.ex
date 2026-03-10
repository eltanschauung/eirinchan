defmodule EirinchanWeb.ReportManagementJSON do
  def index(%{reports: reports}) do
    %{data: Enum.map(reports, &report_data/1)}
  end

  defp report_data(report) do
    %{
      id: report.id,
      board_id: report.board_id,
      post_id: report.post_id,
      thread_id: report.thread_id,
      reason: report.reason,
      ip: report.ip,
      inserted_at: report.inserted_at,
      post_body: report.post && report.post.body
    }
  end
end
