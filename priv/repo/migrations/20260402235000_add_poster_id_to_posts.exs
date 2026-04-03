defmodule Eirinchan.Repo.Migrations.AddPosterIdToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :poster_id, :string
    end
  end
end
