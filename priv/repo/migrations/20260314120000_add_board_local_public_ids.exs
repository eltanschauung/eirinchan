defmodule Eirinchan.Repo.Migrations.AddBoardLocalPublicIds do
  use Ecto.Migration

  def up do
    alter table(:boards) do
      add :next_public_post_id, :integer, null: false, default: 1
    end

    alter table(:posts) do
      add :public_id, :integer
    end

    execute("""
    WITH ranked AS (
      SELECT id,
             ROW_NUMBER() OVER (PARTITION BY board_id ORDER BY inserted_at ASC, id ASC) AS public_id
      FROM posts
    )
    UPDATE posts
    SET public_id = ranked.public_id
    FROM ranked
    WHERE posts.id = ranked.id
    """)

    execute("ALTER TABLE posts ALTER COLUMN public_id SET NOT NULL")

    create unique_index(:posts, [:board_id, :public_id])

    execute("""
    UPDATE boards
    SET next_public_post_id = COALESCE((
      SELECT MAX(posts.public_id) + 1
      FROM posts
      WHERE posts.board_id = boards.id
    ), 1)
    """)
  end

  def down do
    drop_if_exists unique_index(:posts, [:board_id, :public_id])

    alter table(:posts) do
      remove :public_id
    end

    alter table(:boards) do
      remove :next_public_post_id
    end
  end
end
