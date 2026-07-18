defmodule Eirinchan.Repo.Migrations.ScopePublicAntispamActivity do
  use Ecto.Migration

  def up do
    alter table(:search_queries) do
      add :activity, :string, null: false, default: "search"
    end

    execute("""
    UPDATE search_queries
    SET activity = 'feedback'
    WHERE board_id IS NULL AND query = 'feedback'
    """)

    drop_if_exists index(:search_queries, [:ip_subnet, :query, :inserted_at])
    drop_if_exists index(:search_queries, [:board_id, :ip_subnet, :query, :inserted_at])
    drop_if_exists index(:search_queries, [:browser_ref, :query, :inserted_at])
    drop_if_exists index(:search_queries, [:client_key, :query, :inserted_at])

    alter table(:search_queries) do
      remove :query
    end

    create index(:search_queries, [:activity, :ip_subnet, :inserted_at])
    create index(:search_queries, [:activity, :browser_ref, :inserted_at])
    create index(:search_queries, [:activity, :client_key, :inserted_at])
    create index(:search_queries, [:activity, :inserted_at])
  end

  def down do
    drop_if_exists index(:search_queries, [:activity, :inserted_at])
    drop_if_exists index(:search_queries, [:activity, :client_key, :inserted_at])
    drop_if_exists index(:search_queries, [:activity, :browser_ref, :inserted_at])
    drop_if_exists index(:search_queries, [:activity, :ip_subnet, :inserted_at])

    alter table(:search_queries) do
      add :query, :string, null: false, default: "legacy"
    end

    create index(:search_queries, [:ip_subnet, :query, :inserted_at])
    create index(:search_queries, [:board_id, :ip_subnet, :query, :inserted_at])
    create index(:search_queries, [:browser_ref, :query, :inserted_at])
    create index(:search_queries, [:client_key, :query, :inserted_at])

    alter table(:search_queries) do
      remove :activity
    end
  end
end
