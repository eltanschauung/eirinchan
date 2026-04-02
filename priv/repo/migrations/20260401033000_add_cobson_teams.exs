defmodule Eirinchan.Repo.Migrations.AddCobsonTeams do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO april_fools_2026 (team, display_name, html_colour, post_count)
    VALUES
      (11, 'Cobson ♠️', '#000000', 0),
      (12, 'Cobson Haters 🥊', '#74eb34', 0)
    ON CONFLICT (team) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        html_colour = EXCLUDED.html_colour
    """)
  end

  def down do
    execute("DELETE FROM april_fools_2026 WHERE team IN (11, 12)")
  end
end
