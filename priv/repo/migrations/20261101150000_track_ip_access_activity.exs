defmodule Eirinchan.Repo.Migrations.TrackIpAccessActivity do
  use Ecto.Migration

  def up do
    alter table(:ip_access_entries) do
      modify :password, :text, from: :string
      add :authenticated_at, :utc_datetime_usec
      add :post_count, :bigint, null: false, default: 0
      add :user_agents, {:array, :text}, null: false, default: []

      add :tracking_started_at, :utc_datetime_usec,
        null: false,
        default: fragment("timezone('UTC', CURRENT_TIMESTAMP)")
    end

    execute(
      "UPDATE ip_access_entries SET authenticated_at = (granted_at AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'UTC' WHERE granted_at IS NOT NULL"
    )

    create constraint(:ip_access_entries, :ip_access_entries_post_count, check: "post_count >= 0")

    create constraint(:ip_access_entries, :ip_access_entries_user_agents,
             check: "cardinality(user_agents) <= 10"
           )

    alter table(:posts) do
      add :user_agent, :text
    end

    create table(:post_auth_contexts, primary_key: false) do
      add :post_id, references(:posts, on_delete: :delete_all), primary_key: true
      add :auth_password, :text
      add :authenticated_at, :utc_datetime_usec
      add :auth_age_seconds, :bigint
      add :country_code, :string, size: 2
    end

    # A bounded, metadata-only conversion. Never prints values, exports rows,
    # rewrites the live configuration, or changes post-deletion credentials.
    flush()
    Eirinchan.CredentialMigration.restore_ip_access_passwords(repo: repo())
  end

  def down do
    drop table(:post_auth_contexts)
    alter table(:posts), do: remove(:user_agent)
    drop constraint(:ip_access_entries, :ip_access_entries_post_count)
    drop constraint(:ip_access_entries, :ip_access_entries_user_agents)

    alter table(:ip_access_entries) do
      remove :authenticated_at
      remove :post_count
      remove :user_agents
      remove :tracking_started_at
    end

    # Deliberately never rehash plaintext values on rollback.
  end
end
