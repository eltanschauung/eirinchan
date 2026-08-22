defmodule Eirinchan.Repo.Migrations.AddWeeklyUniqueVisitorRollups do
  use Ecto.Migration

  def change do
    alter table(:statistics_snapshots) do
      add :weekly_period_start, :utc_datetime_usec
      add :weekly_unique_visitors, :bigint
    end

    create table(:statistics_weekly_visitors, primary_key: false) do
      add :week_start, :utc_datetime_usec, null: false, primary_key: true
      add :browser_ref, :string, null: false, primary_key: true

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end
end
