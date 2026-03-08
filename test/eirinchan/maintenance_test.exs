defmodule Eirinchan.MaintenanceTest do
  use Eirinchan.DataCase, async: false

  import Ecto.Query

  alias Eirinchan.{Antispam, Bans, Maintenance}

  test "run purges expired bans and old antispam entries" do
    board = board_fixture()

    {:ok, _expired_ban} =
      Bans.create_ban(%{
        board_id: board.id,
        ip_subnet: "203.0.113.0/24",
        reason: "expired",
        active: true,
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    {:ok, _fresh_ban} =
      Bans.create_ban(%{
        board_id: board.id,
        ip_subnet: "203.0.113.0/24",
        reason: "fresh",
        active: true,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    stale_request = %{remote_ip: {198, 51, 100, 20}}
    {:ok, flood_entry} = Antispam.log_post(board, %{"body" => "old"}, stale_request)
    {:ok, search_entry} = Antispam.log_search_query("old", stale_request, board_id: board.id)

    stale_time =
      DateTime.add(DateTime.utc_now(), -172_900, :second) |> DateTime.truncate(:microsecond)

    Repo.update_all(
      from(e in Eirinchan.Antispam.FloodEntry, where: e.id == ^flood_entry.id),
      set: [inserted_at: stale_time]
    )

    Repo.update_all(
      from(e in Eirinchan.Antispam.SearchQuery, where: e.id == ^search_entry.id),
      set: [inserted_at: stale_time]
    )

    config = %{
      auto_maintenance: true,
      maintenance_interval_seconds: 1,
      antispam_retention_seconds: 172_800
    }

    assert {:ok, %{bans: 1, antispam: 2}} = Maintenance.run(config, repo: Repo)
    assert length(Bans.list_bans(board_id: board.id, repo: Repo)) == 1
    assert Antispam.list_flood_entries("198.51.100.20", repo: Repo) == []
    assert Antispam.list_search_queries("198.51.100.20", repo: Repo) == []
  end
end
