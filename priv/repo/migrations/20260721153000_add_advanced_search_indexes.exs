defmodule Eirinchan.Repo.Migrations.AddAdvancedSearchIndexes do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    execute("""
    CREATE INDEX IF NOT EXISTS posts_body_trgm_index
    ON posts USING gin (body gin_trgm_ops)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS posts_subject_trgm_index
    ON posts USING gin (subject gin_trgm_ops)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS posts_name_trgm_index
    ON posts USING gin (name gin_trgm_ops)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS posts_filename_trgm_index
    ON posts USING gin (file_name gin_trgm_ops)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS post_files_filename_trgm_index
    ON post_files USING gin (file_name gin_trgm_ops)
    """)

    create_if_not_exists index(:posts, [:board_id, :inserted_at, :id], name: :posts_search_order_index)
    create_if_not_exists index(:posts, [:file_md5], name: :posts_file_md5_index)
    create_if_not_exists index(:posts, [:poster_id], name: :posts_poster_id_index)
    create_if_not_exists index(:posts, [:image_width, :image_height], name: :posts_dimensions_index)
    create_if_not_exists index(:post_files, [:file_md5], name: :post_files_file_md5_index)
    create_if_not_exists index(:post_files, [:image_width, :image_height], name: :post_files_dimensions_index)
    execute("CREATE INDEX IF NOT EXISTS posts_flag_codes_gin_index ON posts USING gin (flag_codes)")
  end

  def down do
    execute("DROP INDEX IF EXISTS posts_flag_codes_gin_index")
    drop_if_exists index(:post_files, [:image_width, :image_height], name: :post_files_dimensions_index)
    drop_if_exists index(:post_files, [:file_md5], name: :post_files_file_md5_index)
    drop_if_exists index(:posts, [:image_width, :image_height], name: :posts_dimensions_index)
    drop_if_exists index(:posts, [:poster_id], name: :posts_poster_id_index)
    drop_if_exists index(:posts, [:file_md5], name: :posts_file_md5_index)
    drop_if_exists index(:posts, [:board_id, :inserted_at, :id], name: :posts_search_order_index)
    execute("DROP INDEX IF EXISTS post_files_filename_trgm_index")
    execute("DROP INDEX IF EXISTS posts_filename_trgm_index")
    execute("DROP INDEX IF EXISTS posts_name_trgm_index")
    execute("DROP INDEX IF EXISTS posts_subject_trgm_index")
    execute("DROP INDEX IF EXISTS posts_body_trgm_index")
  end
end
