defmodule Eirinchan.Repo.Migrations.AddFutaTeamRow do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO april_fools_2026 (team, display_name, html_colour, post_count)
    VALUES (7, 'FUTA 🍆', '#9542f5', 0)
    ON CONFLICT (team) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        html_colour = EXCLUDED.html_colour
    """)
  end

  def down do
    execute("DELETE FROM april_fools_2026 WHERE team = 7")
  end
end
