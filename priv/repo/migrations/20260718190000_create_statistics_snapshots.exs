defmodule Eirinchan.Repo.Migrations.CreateStatisticsSnapshots do
  use Ecto.Migration

  def change do
    create table(:statistics_snapshots) do
      add :period_start, :utc_datetime_usec, null: false
      add :period_end, :utc_datetime_usec, null: false
      add :captured_at, :utc_datetime_usec
      add :posts_per_hour, :bigint
      add :threads_per_hour, :bigint
      add :users_10minutes, :bigint
      add :counters, :map, null: false, default: fragment("'{}'::jsonb")
      add :daily_total_requests, :bigint
      add :daily_unique_visitors, :bigint
      add :finalized, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:statistics_snapshots, [:period_start])
    create index(:statistics_snapshots, [:finalized, :period_start])
  end
end
