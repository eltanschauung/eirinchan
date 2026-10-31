defmodule Eirinchan.Repo.Migrations.CreateModerationPostEvents do
  use Ecto.Migration

  def change do
    create table(:moderation_post_events) do
      add :action, :string, null: false
      add :mod_user_id, references(:mod_users, on_delete: :nilify_all)
      add :ban_id, references(:bans, on_delete: :nilify_all)
      # Deliberately not foreign keys: evidence survives post/board deletion.
      add :post_id, :bigint, null: false
      add :public_post_id, :bigint, null: false
      add :board_uri, :string, null: false
      add :ip_subnet, :string, null: false
      add :banned_subnet, :string, null: false
      add :file_count, :integer, null: false
      add :files, :map, null: false, default: fragment("'[]'::jsonb")

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:moderation_post_events, [:board_uri, :public_post_id])
    create index(:moderation_post_events, [:ip_subnet, :inserted_at])
    create index(:moderation_post_events, [:inserted_at])

    create constraint(:moderation_post_events, :moderation_post_events_file_count,
             check: "file_count >= 0 AND jsonb_array_length(files) = file_count"
           )
  end
end
