defmodule Eirinchan.Repo.Migrations.AddThreadWatchActivation do
  use Ecto.Migration

  def change do
    alter table(:thread_watches) do
      add :activated, :boolean, null: false, default: true
    end
  end
end
