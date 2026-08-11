defmodule Eirinchan.Repo.Migrations.AddThreadFingerprintToPosts do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("ALTER TABLE posts ADD COLUMN IF NOT EXISTS thread_fingerprint varchar(64)")

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS posts_recent_thread_fingerprint_index
    ON posts (board_id, thread_fingerprint, inserted_at)
    WHERE thread_id IS NULL AND thread_fingerprint IS NOT NULL
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS posts_recent_thread_fingerprint_index")
    execute("ALTER TABLE posts DROP COLUMN IF EXISTS thread_fingerprint")
  end
end
