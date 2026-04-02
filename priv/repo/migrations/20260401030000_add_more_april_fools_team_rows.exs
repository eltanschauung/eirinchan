defmodule Eirinchan.Repo.Migrations.AddMoreAprilFoolsTeamRows do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO april_fools_2026 (team, display_name, html_colour, post_count)
    VALUES
      (8, 'Touhou Project ☯ ⛩️', '#E15467', 0),
      (9, 'Blue Archive ᕕ(◠ڼ◠)ᕗ 😭', '#87CEEB', 0),
      (10, 'Limbus Company ⏰🔥', '#d93c27', 0)
    ON CONFLICT (team) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        html_colour = EXCLUDED.html_colour
    """)
  end

  def down do
    execute("DELETE FROM april_fools_2026 WHERE team IN (8, 9, 10)")
  end
end
