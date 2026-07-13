defmodule Eirinchan.Repo.Migrations.HardenIpAccessEntries do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM ip_access_entries
    WHERE ctid IN (
      SELECT ctid
      FROM (
        SELECT ctid,
               row_number() OVER (
                 PARTITION BY ip
                 ORDER BY granted_at DESC NULLS LAST, ctid DESC
               ) AS duplicate_number
        FROM ip_access_entries
      ) duplicates
      WHERE duplicate_number > 1
    )
    """)

    drop index(:ip_access_entries, [:ip])
    create unique_index(:ip_access_entries, [:ip])
  end

  def down do
    drop unique_index(:ip_access_entries, [:ip])
    create index(:ip_access_entries, [:ip])
  end
end
