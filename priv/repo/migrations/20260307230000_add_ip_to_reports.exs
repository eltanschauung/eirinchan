defmodule Eirinchan.Repo.Migrations.AddIpToReports do
  use Ecto.Migration

  def change do
    alter table(:reports) do
      add :ip, :string
    end

    create index(:reports, [:ip])
  end
end
