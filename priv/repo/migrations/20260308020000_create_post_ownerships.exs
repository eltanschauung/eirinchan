defmodule Eirinchan.Repo.Migrations.CreatePostOwnerships do
  use Ecto.Migration

  def change do
    create table(:post_ownerships) do
      add :browser_token, :string, null: false
      add :post_id, references(:posts, on_delete: :delete_all), null: false

      timestamps(updated_at: false)
    end

    create unique_index(:post_ownerships, [:browser_token, :post_id])
    create index(:post_ownerships, [:post_id])
  end
end
