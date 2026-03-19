defmodule Eirinchan.Repo.Migrations.AddAllBoardsToModUsers do
  use Ecto.Migration

  def change do
    alter table(:mod_users) do
      add :all_boards, :boolean, null: false, default: false
    end
  end
end
