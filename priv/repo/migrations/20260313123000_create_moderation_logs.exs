defmodule Eirinchan.Repo.Migrations.CreateModerationLogs do
  use Ecto.Migration

  def change do
    create table(:moderation_logs) do
      add :mod_user_id, references(:mod_users, on_delete: :nilify_all)
      add :actor_ip, :string
      add :board_uri, :string
      add :text, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:moderation_logs, [:mod_user_id, :inserted_at])
    create index(:moderation_logs, [:board_uri, :inserted_at])
    create index(:moderation_logs, [:inserted_at])
  end
end
