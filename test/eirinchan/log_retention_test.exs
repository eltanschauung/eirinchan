defmodule Eirinchan.LogRetentionTest do
  use Eirinchan.DataCase, async: false

  import Ecto.Query

  alias Eirinchan.{AccessLog, LogRetention, ModerationLog}
  alias Eirinchan.Moderation.LogEntry

  test "weekly retention removes only logging data older than seven whole days" do
    now = ~U[2026-07-14 04:00:00Z]
    cutoff = ~U[2026-07-07 04:00:00Z]

    {:ok, old_log} = ModerationLog.log_action(%{text: "old audit"})
    {:ok, fresh_log} = ModerationLog.log_action(%{text: "fresh audit"})

    Repo.update_all(from(log in LogEntry, where: log.id == ^old_log.id),
      set: [inserted_at: DateTime.add(cutoff, -1, :second)]
    )

    Repo.update_all(from(log in LogEntry, where: log.id == ^fresh_log.id),
      set: [inserted_at: cutoff]
    )

    path =
      Path.join(System.tmp_dir!(), "eirinchan-retention-#{System.unique_integer([:positive])}.log")

    server = start_supervised!({AccessLog, name: nil, path: path})
    on_exit(fn -> File.rm(path) end)

    :ok =
      AccessLog.write(
        "old - - [07/Jul/2026:03:59:59 +0000] \"GET /old HTTP/1.1\" 200 1 \"-\" \"-\"\n" <>
          "fresh - - [07/Jul/2026:04:00:00 +0000] \"GET /new HTTP/1.1\" 200 1 \"-\" \"-\"\n",
        server
      )

    assert {:ok,
            %{access_lines: 1, cutoff: "2026-07-07T04:00:00Z", moderation_rows: 1}} =
             LogRetention.run(
               now: now,
               retention_days: 7,
               repo: Repo,
               access_log_server: server
             )

    assert File.read!(path) =~ "GET /new"
    refute File.read!(path) =~ "GET /old"
    assert Repo.get(LogEntry, old_log.id) == nil
    assert Repo.get(LogEntry, fresh_log.id)
  end
end
