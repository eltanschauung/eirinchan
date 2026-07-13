defmodule Eirinchan.Repo.Migrations.AddBrowserDimensionsToAntispam do
  use Ecto.Migration

  def change do
    alter table(:flood_entries) do
      add :browser_ref, :string
      add :client_key, :string
    end

    create index(:flood_entries, [:browser_ref, :inserted_at])
    create index(:flood_entries, [:client_key, :inserted_at])
    create index(:flood_entries, [:inserted_at])

    alter table(:search_queries) do
      add :browser_ref, :string
      add :client_key, :string
    end

    create index(:search_queries, [:browser_ref, :query, :inserted_at])
    create index(:search_queries, [:client_key, :query, :inserted_at])
    create index(:search_queries, [:inserted_at])
  end
end
