defmodule Mix.Tasks.EirinchanMaintenanceTest do
  use Eirinchan.DataCase, async: false

  import ExUnit.CaptureIO

  test "maintenance task prints summary" do
    output =
      capture_io(fn ->
        Mix.Tasks.Eirinchan.Maintenance.run([])
      end)

    assert output =~ "bans="
    assert output =~ "antispam="
  end
end
