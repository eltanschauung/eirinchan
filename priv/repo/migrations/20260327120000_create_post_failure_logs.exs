defmodule Eirinchan.Repo.Migrations.CreatePostFailureLogs do
  use Ecto.Migration

  def change do
    create table(:post_failure_logs) do
      add :event, :string, null: false
      add :level, :string, null: false
      add :board_uri, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:post_failure_logs, [:event])
    create index(:post_failure_logs, [:board_uri])
    create index(:post_failure_logs, [:inserted_at])
  end
end
