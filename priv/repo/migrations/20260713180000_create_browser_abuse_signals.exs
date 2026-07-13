defmodule Eirinchan.Repo.Migrations.CreateBrowserAbuseSignals do
  use Ecto.Migration

  def change do
    create table(:browser_abuse_signals, primary_key: false) do
      add :browser_ref, :string, primary_key: true
      add :client_key, :string
      add :reason, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:browser_abuse_signals, [:expires_at])
  end
end
