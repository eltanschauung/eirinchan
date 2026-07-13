defmodule Eirinchan.Repo.Migrations.CreateBrowserIdentities do
  use Ecto.Migration

  def up do
    create table(:browser_identities, primary_key: false) do
      add :browser_ref, :string, primary_key: true
      add :issued_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: false
    end

    create index(:browser_identities, [:expires_at])

    execute("""
    INSERT INTO browser_identities (browser_ref, issued_at, last_seen_at, expires_at)
    SELECT browser_ref, NOW(), NOW(), NOW() + INTERVAL '400 days'
    FROM (
      SELECT browser_token AS browser_ref FROM post_ownerships
      UNION
      SELECT browser_token AS browser_ref FROM thread_watches
    ) AS existing_references
    ON CONFLICT (browser_ref) DO NOTHING
    """)
  end

  def down do
    drop table(:browser_identities)
  end
end
