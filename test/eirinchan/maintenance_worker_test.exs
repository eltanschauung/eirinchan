defmodule Eirinchan.MaintenanceWorkerTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.MaintenanceWorker

  test "runs maintenance outside the request pipeline" do
    board = board_fixture()

    {:ok, _ban} =
      Eirinchan.Bans.create_ban(%{
        board_id: board.id,
        ip_subnet: "203.0.113.0/24",
        reason: "expired",
        active: true,
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    config = %{
      maintenance_interval_seconds: 0,
      antispam_retention_seconds: 172_800,
      post_failure_log_retention_days: 7
    }

    worker = start_supervised!({MaintenanceWorker,
      name: nil,
      repo: Repo,
      config_provider: fn -> config end,
      initial_delay_ms: 60_000
    })

    assert {:ok, %{bans: 1}} = MaintenanceWorker.run_now(worker)
    assert Eirinchan.Bans.list_bans(board_id: board.id) == []
  end
end
