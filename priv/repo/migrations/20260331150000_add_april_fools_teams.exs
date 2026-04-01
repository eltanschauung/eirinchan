defmodule Eirinchan.Repo.Migrations.AddAprilFoolsTeams do
  use Ecto.Migration

  def up do
    alter table(:posts) do
      add :team, :integer
    end

    create table(:april_fools_2026, primary_key: false) do
      add :team, :integer, primary_key: true
      add :display_name, :string, null: false
      add :html_colour, :string, null: false
      add :post_count, :integer, null: false, default: 0
    end

    execute("""
    INSERT INTO april_fools_2026 (team, display_name, html_colour, post_count)
    VALUES
      (1, 'Yukari Whale 🐋', '#FFBF00', 0),
      (2, 'Judaism ✡', '#000080', 0),
      (3, 'Otokonoko 🩰', '#FF69B4', 0),
      (4, 'Skuf 🍟', '#013220', 0),
      (5, 'Soyteen 💎', '#A0BBC7', 0),
      (6, 'Finasteride 💊', '#ADD8E6', 0)
    """)
  end

  def down do
    drop table(:april_fools_2026)

    alter table(:posts) do
      remove :team
    end
  end
end
