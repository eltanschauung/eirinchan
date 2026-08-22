defmodule Eirinchan.Statistics.WeekTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Statistics.Week

  defmodule UTC do
    def local_naive(datetime), do: DateTime.to_naive(datetime)
    def utc_datetime(datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")
  end

  test "uses Sunday through Saturday calendar weeks" do
    assert Week.start_at(~U[2026-08-22 12:00:00Z], UTC) == ~U[2026-08-16 00:00:00Z]
    assert Week.start_at(~U[2026-08-23 00:00:00Z], UTC) == ~U[2026-08-23 00:00:00Z]
  end

  test "returns a completed week only at Sunday midnight" do
    assert Week.completed_week_start(~U[2026-08-23 00:00:00Z], UTC) ==
             ~U[2026-08-16 00:00:00Z]

    refute Week.completed_week_start(~U[2026-08-22 23:00:00Z], UTC)
    refute Week.completed_week_start(~U[2026-08-23 01:00:00Z], UTC)
  end

  test "calculates the exclusive end of a week" do
    assert Week.end_at(~U[2026-08-16 00:00:00Z], UTC) == ~U[2026-08-23 00:00:00Z]
  end
end
