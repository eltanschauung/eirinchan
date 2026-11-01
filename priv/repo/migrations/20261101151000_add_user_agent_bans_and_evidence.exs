defmodule Eirinchan.Repo.Migrations.AddUserAgentBansAndEvidence do
  use Ecto.Migration

  def change do
    alter table(:bans) do
      modify :ip_subnet, :string, null: true, from: {:string, null: false}
      add :user_agent, :text
    end

    create constraint(:bans, :bans_target,
             check:
               "NULLIF(btrim(ip_subnet), '') IS NOT NULL OR NULLIF(btrim(user_agent), '') IS NOT NULL"
           )

    alter table(:moderation_post_events) do
      add :user_agent, :text
      add :auth_password, :text
      add :authenticated_at, :utc_datetime_usec
      add :auth_age_seconds, :bigint
      add :auth_age_at_ban_seconds, :bigint
      add :country_code, :string, size: 2
    end
  end
end
