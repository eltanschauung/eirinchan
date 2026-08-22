defmodule Eirinchan.Statistics.Snapshot do
  use Ecto.Schema

  import Ecto.Changeset

  schema "statistics_snapshots" do
    field :period_start, :utc_datetime_usec
    field :period_end, :utc_datetime_usec
    field :captured_at, :utc_datetime_usec
    field :posts_per_hour, :integer
    field :threads_per_hour, :integer
    field :users_10minutes, :integer
    field :counters, :map, default: %{}
    field :daily_board_ppd, :map
    field :daily_total_requests, :integer
    field :daily_unique_visitors, :integer
    field :weekly_period_start, :utc_datetime
    field :weekly_unique_visitors, :integer
    field :finalized, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :period_start,
      :period_end,
      :captured_at,
      :posts_per_hour,
      :threads_per_hour,
      :users_10minutes,
      :counters,
      :daily_board_ppd,
      :daily_total_requests,
      :daily_unique_visitors,
      :weekly_period_start,
      :weekly_unique_visitors,
      :finalized
    ])
    |> validate_required([:period_start, :period_end, :counters, :finalized])
    |> unique_constraint(:period_start)
  end
end
