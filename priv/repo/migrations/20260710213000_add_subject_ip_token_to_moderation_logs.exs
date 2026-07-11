defmodule Eirinchan.Repo.Migrations.AddSubjectIpTokenToModerationLogs do
  use Ecto.Migration

  def change do
    alter table(:moderation_logs) do
      add :subject_ip_token, :string
    end

    create index(:moderation_logs, [:subject_ip_token, :inserted_at])
  end
end
