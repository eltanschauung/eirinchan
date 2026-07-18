defmodule Eirinchan.Repo.Migrations.ScopeFloodEntriesByActivity do
  use Ecto.Migration

  def change do
    alter table(:flood_entries) do
      add :activity, :string, null: false, default: "post"
    end

    create index(:flood_entries, [:activity, :ip_subnet, :inserted_at])
    create index(:flood_entries, [:activity, :browser_ref, :inserted_at])
    create index(:flood_entries, [:activity, :client_key, :inserted_at])
    create index(:flood_entries, [:activity, :inserted_at])
  end
end
