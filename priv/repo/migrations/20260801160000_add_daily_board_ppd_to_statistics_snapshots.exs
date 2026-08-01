defmodule Eirinchan.Repo.Migrations.AddDailyBoardPpdToStatisticsSnapshots do
  use Ecto.Migration

  def change do
    alter table(:statistics_snapshots) do
      add :daily_board_ppd, :map
    end
  end
end
