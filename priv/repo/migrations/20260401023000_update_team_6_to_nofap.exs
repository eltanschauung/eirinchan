defmodule Eirinchan.Repo.Migrations.UpdateTeam6ToNofap do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE april_fools_2026
    SET display_name = 'Nofap 🔞',
        html_colour = '#abd0f5'
    WHERE team = 6
    """)
  end

  def down do
    execute("""
    UPDATE april_fools_2026
    SET display_name = 'Finasteride 💊',
        html_colour = '#ADD8E6'
    WHERE team = 6
    """)
  end
end
