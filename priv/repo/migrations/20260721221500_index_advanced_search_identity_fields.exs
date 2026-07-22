defmodule Eirinchan.Repo.Migrations.IndexAdvancedSearchIdentityFields do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    for field <- ~w(tripcode email poster_id) do
      execute("""
      CREATE INDEX CONCURRENTLY IF NOT EXISTS posts_#{field}_trgm_index
      ON posts USING gin (#{field} gin_trgm_ops)
      """)
    end
  end

  def down do
    for field <- ~w(tripcode email poster_id) do
      execute("DROP INDEX CONCURRENTLY IF EXISTS posts_#{field}_trgm_index")
    end
  end
end
