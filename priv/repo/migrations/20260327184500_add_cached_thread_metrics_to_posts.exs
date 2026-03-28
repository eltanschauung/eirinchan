defmodule Eirinchan.Repo.Migrations.AddCachedThreadMetricsToPosts do
  use Ecto.Migration

  def up do
    alter table(:posts) do
      add :cached_reply_count, :integer, default: 0, null: false
      add :cached_image_count, :integer, default: 0, null: false
      add :cached_last_reply_at, :utc_datetime_usec
    end

    execute("""
    UPDATE posts AS thread
    SET
      cached_reply_count = COALESCE(reply_stats.reply_count, 0),
      cached_image_count = COALESCE(primary_image_stats.primary_image_count, 0) + COALESCE(extra_image_stats.extra_image_count, 0),
      cached_last_reply_at = reply_stats.cached_last_reply_at
    FROM (
      SELECT
        p.id AS thread_id,
        COUNT(r.id) AS reply_count,
        MAX(r.inserted_at) AS cached_last_reply_at
      FROM posts p
      LEFT JOIN posts r ON r.thread_id = p.id
      WHERE p.thread_id IS NULL
      GROUP BY p.id
    ) AS reply_stats
    LEFT JOIN (
      SELECT
        p.id AS thread_id,
        COUNT(media.id) FILTER (
          WHERE media.file_path IS NOT NULL
            AND media.file_path <> ''
            AND media.file_path <> 'deleted'
            AND media.file_type LIKE 'image/%'
        ) AS primary_image_count
      FROM posts p
      LEFT JOIN posts media ON media.id = p.id OR media.thread_id = p.id
      WHERE p.thread_id IS NULL
      GROUP BY p.id
    ) AS primary_image_stats ON primary_image_stats.thread_id = reply_stats.thread_id
    LEFT JOIN (
      SELECT
        thread.id AS thread_id,
        COUNT(post_files.id) FILTER (
          WHERE post_files.file_path IS NOT NULL
            AND post_files.file_path <> ''
            AND post_files.file_path <> 'deleted'
            AND post_files.file_type LIKE 'image/%'
        ) AS extra_image_count
      FROM posts thread
      LEFT JOIN posts member ON member.id = thread.id OR member.thread_id = thread.id
      LEFT JOIN post_files ON post_files.post_id = member.id
      WHERE thread.thread_id IS NULL
      GROUP BY thread.id
    ) AS extra_image_stats ON extra_image_stats.thread_id = reply_stats.thread_id
    WHERE thread.id = reply_stats.thread_id
      AND thread.thread_id IS NULL
    """)
  end

  def down do
    alter table(:posts) do
      remove :cached_last_reply_at
      remove :cached_image_count
      remove :cached_reply_count
    end
  end
end
