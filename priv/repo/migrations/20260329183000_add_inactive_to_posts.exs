defmodule Eirinchan.Repo.Migrations.AddInactiveToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :inactive, :boolean, default: false, null: false
    end
  end
end
