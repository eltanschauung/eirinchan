defmodule Eirinchan.Repo.Migrations.AddDuplicatePostFingerprintToPosts do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("ALTER TABLE posts ADD COLUMN IF NOT EXISTS duplicate_post_fingerprint varchar(64)")
    execute("ALTER TABLE posts ADD COLUMN IF NOT EXISTS duplicate_post_identity varchar(43)")

    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS posts_recent_duplicate_post_index
    ON posts (board_id, duplicate_post_identity, duplicate_post_fingerprint, inserted_at)
    WHERE duplicate_post_identity IS NOT NULL AND duplicate_post_fingerprint IS NOT NULL
    """)
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS posts_recent_duplicate_post_index")
    execute("ALTER TABLE posts DROP COLUMN IF EXISTS duplicate_post_identity")
    execute("ALTER TABLE posts DROP COLUMN IF EXISTS duplicate_post_fingerprint")
  end
end
