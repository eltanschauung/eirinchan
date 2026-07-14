defmodule Eirinchan.HealthLogWorkerTest do
  use Eirinchan.DataCase, async: false

  import ExUnit.CaptureLog

  alias Eirinchan.{AccessLog, HealthLogWorker}

  test "records bounded VM, database, and access-writer health" do
    path =
      Path.join(System.tmp_dir!(), "eirinchan-health-#{System.unique_integer([:positive])}.log")

    access_log = start_supervised!({AccessLog, name: nil, path: path})

    worker =
      start_supervised!(
        {HealthLogWorker,
         name: nil,
         repo: Repo,
         access_log_server: access_log,
         interval_ms: 60_000,
         initial_delay_ms: 60_000}
      )

    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    on_exit(fn -> File.rm(path) end)

    log = capture_log(fn -> assert {:ok, _payload} = HealthLogWorker.run_now(worker) end)

    assert log =~ "health.snapshot"
    assert log =~ ~s|"status":"ok"|
    assert log =~ ~s|"vm_memory_bytes":{|
    assert log =~ ~s|"access_log":{|
    refute log =~ "SELECT 1"
  end
end
