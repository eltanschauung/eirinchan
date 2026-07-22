defmodule Eirinchan.Statistics.ReportTest do
  use Eirinchan.DataCase

  alias Eirinchan.Repo
  alias Eirinchan.Statistics.Report
  alias Eirinchan.Statistics.Snapshot

  test "returns the selected window, its baseline, and bounded challenge guidance" do
    now = ~U[2026-07-18 12:30:00Z]

    insert_snapshot(~U[2026-07-18 08:00:00Z], 50, 2, 1, 8)
    insert_snapshot(~U[2026-07-18 09:00:00Z], 50, 3, 1, 10)
    insert_snapshot(~U[2026-07-18 10:00:00Z], 90, 4, 2, 12)
    insert_snapshot(~U[2026-07-18 11:00:00Z], 90, 5, 2, 14)

    report = Report.build(2, repo: Repo, now: now)

    assert report.timeframe_hours == 2
    assert report.previous.requests == 100
    assert report.current.requests == 180
    assert report.current.posts == 9
    assert report.current.threads == 4
    assert report.current.visitors_10minutes == %{latest: 14, average: 13.0, maximum: 14}
    assert report.current.rate_limits == %{"search" => 2, "total" => 2}
    assert report.current.search.attempts == 2
    assert report.current.search.features == %{"text" => 2}

    assert report.current.search.clients.networks == [
             %{identifier: "network-id", count: 2}
           ]

    assert report.current.search.clients.network_features == [
             %{identifier: "network-id", feature: "text", count: 2}
           ]

    assert report.traffic_comparison.change_percent == 80.0
    assert report.traffic_comparison.suggested_challenge_increment == 1
    assert report.traffic_comparison.baseline_complete
    assert length(report.current.snapshots) == 2
  end

  test "does not recommend escalation from an incomplete or zero baseline" do
    now = ~U[2026-07-18 12:30:00Z]
    insert_snapshot(~U[2026-07-18 11:00:00Z], 500, 1, 1, 4)

    report = Report.build(1, repo: Repo, now: now)

    refute report.traffic_comparison.baseline_complete
    assert is_nil(report.traffic_comparison.change_percent)
    assert report.traffic_comparison.suggested_challenge_increment == 0
  end

  test "uses the configured traffic increase per challenge step" do
    now = ~U[2026-07-18 12:30:00Z]
    insert_snapshot(~U[2026-07-18 10:00:00Z], 100, 1, 1, 4)
    insert_snapshot(~U[2026-07-18 11:00:00Z], 150, 1, 1, 4)

    report =
      Report.build(1,
        repo: Repo,
        now: now,
        config: %{statistics_challenge_step_percent: 25}
      )

    assert report.traffic_comparison.challenge_step_percent == 25
    assert report.traffic_comparison.suggested_challenge_increment == 2
  end

  defp insert_snapshot(period_start, requests, posts, threads, visitors) do
    period_end = DateTime.add(period_start, 3_600, :second)

    %Snapshot{}
    |> Snapshot.changeset(%{
      period_start: period_start,
      period_end: period_end,
      captured_at: period_end,
      posts_per_hour: posts,
      threads_per_hour: threads,
      users_10minutes: visitors,
      counters: %{
        "requests.total" => requests,
        "rate_limits.search" => 1,
        "rate_limits.total" => 1,
        "search.attempts" => 1,
        "search.features.text" => 1,
        "search.clients.network.network-id" => 1,
        "search.client_features.network.network-id.text" => 1
      },
      finalized: true
    })
    |> Repo.insert!()
  end
end
