defmodule Eirinchan.Repo.Migrations.CreateThreadWatches do
  use Ecto.Migration

  def change do
    create table(:thread_watches) do
      add :browser_token, :string, null: false
      add :board_uri, :string, null: false
      add :thread_id, :integer, null: false
      add :last_seen_post_id, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:thread_watches, [:browser_token, :board_uri, :thread_id])
    create index(:thread_watches, [:browser_token, :updated_at])
    create index(:thread_watches, [:board_uri, :thread_id])
  end
end
