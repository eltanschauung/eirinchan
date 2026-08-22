defmodule Eirinchan.Statistics.WeeklyVisitor do
  use Ecto.Schema

  @primary_key false
  schema "statistics_weekly_visitors" do
    field :week_start, :utc_datetime, primary_key: true
    field :browser_ref, :string, primary_key: true

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
