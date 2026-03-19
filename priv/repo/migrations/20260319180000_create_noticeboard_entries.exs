defmodule Eirinchan.Repo.Migrations.CreateNoticeboardEntries do
  use Ecto.Migration

  def change do
    create table(:noticeboard_entries) do
      add :subject, :string
      add :body_html, :text, null: false
      add :author_name, :string, null: false
      add :posted_at, :naive_datetime_usec, null: false
      add :mod_user_id, references(:mod_users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:noticeboard_entries, [:posted_at])
  end
end
