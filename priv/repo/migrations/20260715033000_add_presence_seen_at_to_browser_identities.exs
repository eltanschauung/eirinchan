defmodule Eirinchan.Repo.Migrations.AddPresenceSeenAtToBrowserIdentities do
  use Ecto.Migration

  def change do
    alter table(:browser_identities) do
      add :presence_seen_at, :utc_datetime
    end

    create index(:browser_identities, [:presence_seen_at])
  end
end
