defmodule Eirinchan.Repo.Migrations.AddLegacyImportIdToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :legacy_import_id, :integer
    end

    create unique_index(:posts, [:board_id, :legacy_import_id],
             where: "legacy_import_id IS NOT NULL",
             name: :posts_board_id_legacy_import_id_index
           )
  end
end
