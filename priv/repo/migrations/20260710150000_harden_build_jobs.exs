defmodule Eirinchan.Repo.Migrations.HardenBuildJobs do
  use Ecto.Migration

  def up do
    alter table(:build_jobs) do
      add :attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :started_at, :utc_datetime_usec
      add :available_at, :utc_datetime_usec
    end

    execute("""
    DELETE FROM build_jobs duplicate
    USING build_jobs keeper
    WHERE duplicate.id > keeper.id
      AND duplicate.board_id = keeper.board_id
      AND duplicate.kind = keeper.kind
      AND COALESCE(duplicate.thread_id, -1) = COALESCE(keeper.thread_id, -1)
      AND duplicate.status IN ('pending', 'running')
      AND keeper.status IN ('pending', 'running')
    """)

    execute("""
    CREATE UNIQUE INDEX build_jobs_active_unique_index
    ON build_jobs (board_id, kind, COALESCE(thread_id, -1))
    WHERE status IN ('pending', 'running')
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS build_jobs_active_unique_index")

    alter table(:build_jobs) do
      remove :available_at
      remove :started_at
      remove :last_error
      remove :attempts
    end
  end
end
