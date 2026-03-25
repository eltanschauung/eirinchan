defmodule Eirinchan.Repo.Migrations.CreateIpAccessEntries do
  use Ecto.Migration

  def change do
    create table(:ip_access_entries, primary_key: false) do
      add :ip, :string, null: false
      add :password, :string
      add :granted_at, :naive_datetime
    end

    create index(:ip_access_entries, [:ip])
  end
end
