defmodule Eirinchan.Repo.Migrations.WidenAprilFoolsTeamPostCount do
  use Ecto.Migration

  def change do
    alter table(:april_fools_2026) do
      modify :post_count, :bigint, null: false, default: 0
    end
  end
end
