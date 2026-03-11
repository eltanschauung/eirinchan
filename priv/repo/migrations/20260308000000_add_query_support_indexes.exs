defmodule Eirinchan.Repo.Migrations.AddQuerySupportIndexes do
  use Ecto.Migration

  def up do
    execute(
      """
      CREATE INDEX IF NOT EXISTS posts_board_thread_listing_idx
      ON posts (board_id, sticky DESC, bump_at DESC, inserted_at DESC, id DESC)
      WHERE thread_id IS NULL
      """,
      "DROP INDEX IF EXISTS posts_board_thread_listing_idx"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS cites_target_post_id_idx ON cites (target_post_id)",
      "DROP INDEX IF EXISTS cites_target_post_id_idx"
    )

    execute(
      "CREATE INDEX IF NOT EXISTS nntp_references_target_post_id_idx ON nntp_references (target_post_id)",
      "DROP INDEX IF EXISTS nntp_references_target_post_id_idx"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS posts_board_thread_listing_idx")
    execute("DROP INDEX IF EXISTS cites_target_post_id_idx")
    execute("DROP INDEX IF EXISTS nntp_references_target_post_id_idx")
  end
end
