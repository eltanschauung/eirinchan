defmodule Eirinchan.Repo.Migrations.NormalizeThreadWatchIdentity do
  use Ecto.Migration

  @new_unique_index :thread_watches_browser_token_thread_id_index
  @thread_foreign_key :thread_watches_thread_id_fkey

  def up do
    execute("LOCK TABLE thread_watches IN SHARE ROW EXCLUSIVE MODE")

    execute("""
    DELETE FROM thread_watches AS watch
    WHERE NOT EXISTS (
      SELECT 1
      FROM posts AS thread
      WHERE thread.id = watch.thread_id
        AND thread.thread_id IS NULL
    )
    """)

    execute("""
    WITH duplicate_groups AS (
      SELECT
        browser_token,
        thread_id,
        MIN(id) AS keep_id,
        MAX(last_seen_post_id) AS last_seen_post_id,
        MAX(updated_at) AS updated_at
      FROM thread_watches
      GROUP BY browser_token, thread_id
      HAVING COUNT(*) > 1
    )
    UPDATE thread_watches AS watch
    SET
      last_seen_post_id = duplicate_groups.last_seen_post_id,
      updated_at = duplicate_groups.updated_at
    FROM duplicate_groups
    WHERE watch.id = duplicate_groups.keep_id
    """)

    execute("""
    WITH duplicate_groups AS (
      SELECT browser_token, thread_id, MIN(id) AS keep_id
      FROM thread_watches
      GROUP BY browser_token, thread_id
      HAVING COUNT(*) > 1
    )
    DELETE FROM thread_watches AS watch
    USING duplicate_groups
    WHERE watch.browser_token = duplicate_groups.browser_token
      AND watch.thread_id = duplicate_groups.thread_id
      AND watch.id <> duplicate_groups.keep_id
    """)

    execute("""
    UPDATE thread_watches AS watch
    SET board_uri = board.uri
    FROM posts AS thread
    JOIN boards AS board ON board.id = thread.board_id
    WHERE thread.id = watch.thread_id
      AND thread.thread_id IS NULL
      AND watch.board_uri <> board.uri
    """)

    execute(
      "ALTER TABLE thread_watches ALTER COLUMN thread_id TYPE bigint USING thread_id::bigint"
    )

    execute(
      "ALTER TABLE thread_watches ALTER COLUMN last_seen_post_id TYPE bigint USING last_seen_post_id::bigint"
    )

    create unique_index(:thread_watches, [:browser_token, :thread_id], name: @new_unique_index)

    execute("""
    ALTER TABLE thread_watches
    ADD CONSTRAINT #{@thread_foreign_key}
    FOREIGN KEY (thread_id) REFERENCES posts(id) ON DELETE CASCADE
    """)
  end

  def down do
    execute("ALTER TABLE thread_watches DROP CONSTRAINT IF EXISTS #{@thread_foreign_key}")

    drop_if_exists unique_index(:thread_watches, [:browser_token, :thread_id],
                     name: @new_unique_index
                   )
  end
end
