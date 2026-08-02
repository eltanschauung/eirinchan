defmodule Eirinchan.Statistics.ChartsTest do
  use Eirinchan.DataCase

  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Statistics.Charts
  alias Eirinchan.Statistics.Snapshot

  defmodule UTC do
    def local_naive(datetime), do: DateTime.to_naive(datetime)
    def utc_datetime(datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")
  end

  test "builds all seven fixed-shape charts and prefers completed snapshots for post counts" do
    now = ~U[2026-08-02 15:30:00Z]
    board = board_fixture()

    post_at(board, ~U[2026-06-05 08:10:00Z])
    post_at(board, ~U[2026-06-05 08:20:00Z])
    post_at(board, ~U[2026-06-06 08:10:00Z])
    post_at(board, ~U[2026-06-06 08:20:00Z])
    post_at(board, ~U[2026-07-15 08:10:00Z])
    post_at(board, ~U[2026-08-01 10:15:00Z])
    post_at(board, ~U[2026-08-02 15:10:00Z])

    insert_snapshot(~U[2026-08-01 10:00:00Z], posts: 7, visitors: 4)

    insert_snapshot(~U[2026-07-31 23:00:00Z],
      posts: 0,
      visitors: 9,
      daily_visitors: 21
    )

    insert_snapshot(~U[2026-08-01 23:00:00Z],
      posts: 0,
      visitors: 11,
      daily_visitors: 31
    )

    for {date, visitors} <- Enum.zip(Date.range(~D[2026-07-26], ~D[2026-08-01]), 1..7) do
      insert_snapshot(DateTime.new!(date, ~T[05:00:00], "Etc/UTC"),
        posts: 0,
        visitors: visitors
      )
    end

    result =
      Charts.build([board.id],
        repo: Repo,
        now: now,
        calendar: UTC,
        current_visitors: 6
      )

    assert length(result.charts) == 7

    current_pph = chart(result, "pph-2026-08-02")
    yesterday_pph = chart(result, "pph-2026-08-01")
    ppd = chart(result, "posts-per-day-past-two-months")
    monthly_posts = chart(result, "posts-per-month-2026")
    current_visitors = chart(result, "visitors-current-month")
    last_month_visitors = chart(result, "visitors-last-month")
    average_visitors = chart(result, "average-visitors-per-hour-last-week")

    assert current_pph.title == "Posts Per Hour - August 2nd 2026"
    assert current_pph.column_count == 24
    assert point(current_pph, "3pm").value == 1
    assert point(current_pph, "3pm").state == :partial
    assert point(current_pph, "4pm").value == 0
    assert point(current_pph, "4pm").state == :future

    assert yesterday_pph.title == "Posts Per Hour - August 1st 2026"
    assert yesterday_pph.column_count == 24
    assert point(yesterday_pph, "10am").value == 7
    assert point(yesterday_pph, "10am").state == :tracked

    assert ppd.title == "Posts Per Day - Past 2 Months"
    assert ppd.column_count == 62
    assert point(ppd, "6/5").value == 2
    assert point(ppd, "6/5").title_label == "June 5th 2026"
    assert point(ppd, "8/1").value == 7
    assert ppd.note =~ "reconstructed from retained posts"

    assert monthly_posts.title == "Posts Per Month - 2026"
    assert monthly_posts.column_count == 12
    assert point(monthly_posts, "June").value == 5
    assert point(monthly_posts, "June").state == :estimated
    assert point(monthly_posts, "July").value == 1
    assert point(monthly_posts, "July").state == :reconstructed
    assert point(monthly_posts, "September").state == :future

    assert current_visitors.title == "Visitors Per Day - August"
    assert current_visitors.column_count == 31
    assert point(current_visitors, "1st").value == 31
    assert point(current_visitors, "1st").title_label == "August 1st 2026"
    assert point(current_visitors, "2nd").value == 6
    assert point(current_visitors, "3rd").state == :future

    assert last_month_visitors.title == "Visitors Per Day - Last Month"
    assert last_month_visitors.column_count == 31
    assert point(last_month_visitors, "1st").state == :unavailable
    assert point(last_month_visitors, "31st").value == 21

    assert average_visitors.title == "Average Visitors Per Hour - Last Week"
    assert average_visitors.column_count == 24
    assert point(average_visitors, "5am").value == 4.0
    assert point(average_visitors, "5am").title_label == "05:00"
    assert point(average_visitors, "5am").samples == 7
    assert point(average_visitors, "6am").state == :unavailable
  end

  test "uses long current and previous date titles" do
    result =
      Charts.build([],
        repo: Repo,
        now: ~U[2026-08-08 12:00:00Z],
        calendar: UTC,
        current_visitors: 0
      )

    assert chart(result, "pph-2026-08-08").title ==
             "Posts Per Hour - August 8th 2026"

    assert chart(result, "pph-2026-08-07").title ==
             "Posts Per Hour - August 7th 2026"

    assert point(chart(result, "pph-2026-08-08"), "12am").title_label == "00:00"
    assert point(chart(result, "pph-2026-08-08"), "3pm").title_label == "15:00"
  end

  test "current-month visitors always reserve every day in a leap February" do
    result =
      Charts.build([],
        repo: Repo,
        now: ~U[2028-02-03 12:00:00Z],
        calendar: UTC,
        current_visitors: 2
      )

    chart = chart(result, "visitors-current-month")

    assert chart.column_count == 29
    assert List.last(chart.points).label == "29th"
    assert List.last(chart.points).state == :future
  end

  test "distinguishes estimated historical snapshots from tracked data" do
    board = board_fixture()

    insert_snapshot(~U[2026-06-05 08:00:00Z],
      posts: 9,
      visitors: 4,
      counters: %{"historical_estimate" => true}
    )

    insert_snapshot(~U[2026-07-02 23:00:00Z],
      posts: 0,
      visitors: 4,
      daily_visitors: 44,
      counters: %{"historical_estimate" => true}
    )

    result =
      Charts.build([board.id],
        repo: Repo,
        now: ~U[2026-08-02 15:30:00Z],
        calendar: UTC,
        current_visitors: 0
      )

    ppd = chart(result, "posts-per-day-past-two-months")
    visitors = chart(result, "visitors-last-month")

    assert point(ppd, "6/5").state == :estimated
    assert point(ppd, "6/5").value == 9

    assert ppd.note ==
             "Data before June 18th 2026 is only approximate, backfilled by analysis of /bant/ post integers and timestamps."

    assert point(visitors, "2nd").state == :estimated
    assert point(visitors, "2nd").value == 44
  end

  defp post_at(board, inserted_at) do
    post = thread_fixture(board)

    Repo.update_all(
      from(stored_post in Post, where: stored_post.id == ^post.id),
      set: [inserted_at: inserted_at, bump_at: inserted_at]
    )

    post
  end

  defp insert_snapshot(period_start, opts) do
    period_end = DateTime.add(period_start, 3_600, :second)

    %Snapshot{}
    |> Snapshot.changeset(%{
      period_start: period_start,
      period_end: period_end,
      captured_at: period_end,
      posts_per_hour: Keyword.fetch!(opts, :posts),
      users_10minutes: Keyword.fetch!(opts, :visitors),
      daily_unique_visitors: Keyword.get(opts, :daily_visitors),
      counters: Keyword.get(opts, :counters, %{}),
      finalized: true
    })
    |> Repo.insert!()
  end

  defp chart(result, id), do: Enum.find(result.charts, &(&1.id == id))
  defp point(chart, label), do: Enum.find(chart.points, &(&1.label == label))
end
