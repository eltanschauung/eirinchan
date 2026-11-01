defmodule Eirinchan.Repo.Migrations.AddPostPolls do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :poll_question, :text
      add :poll_options, {:array, :text}, null: false, default: []
    end

    create constraint(:posts, :posts_poll_shape,
             check:
               "(poll_question IS NULL AND cardinality(poll_options) = 0) OR " <>
                 "(poll_question IS NOT NULL AND char_length(poll_question) BETWEEN 1 AND 300 " <>
                 "AND cardinality(poll_options) BETWEEN 2 AND 6)"
           )

    create table(:poll_votes) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :choice, :integer, null: false
      add :ip_ref, :string, null: false
      add :browser_ref, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:poll_votes, [:post_id, :ip_ref])
    create unique_index(:poll_votes, [:post_id, :browser_ref], where: "browser_ref IS NOT NULL")
    create constraint(:poll_votes, :poll_votes_choice, check: "choice BETWEEN 0 AND 5")
  end
end
