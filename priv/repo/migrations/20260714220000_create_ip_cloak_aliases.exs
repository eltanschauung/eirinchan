defmodule Eirinchan.Repo.Migrations.CreateIpCloakAliases do
  use Ecto.Migration

  def change do
    create table(:ip_cloak_aliases) do
      add :token, :string, null: false
      add :payload, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:ip_cloak_aliases, [:token])
    create index(:ip_cloak_aliases, [:expires_at])
  end
end
