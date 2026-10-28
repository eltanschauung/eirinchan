defmodule Eirinchan.AntispamConcurrencyRepo do
  use Ecto.Repo, otp_app: :eirinchan, adapter: Ecto.Adapters.Postgres
end

defmodule Eirinchan.AntispamConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Eirinchan.{Antispam, AntispamConcurrencyRepo, Boards, Repo}
  alias Eirinchan.Antispam.FloodEntry
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Runtime.Config

  test "equivalent actions on different boards serialize a shared global quota" do
    assert_shared_quota(:public_action)
  end

  test "concurrent upload attempts serialize the shared post quota" do
    assert_shared_quota(:upload)
  end

  defp assert_shared_quota(kind) do
    opts = Repo.config()
    assert Keyword.get(opts, :hostname) in ["localhost", "127.0.0.1", "::1"]
    # Phoenix appends MIX_TEST_PARTITION digits to the standard test name.
    assert Regex.match?(~r/_test[0-9]*$/, Keyword.get(opts, :database, ""))

    opts =
      opts
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 4)
      |> Keyword.put(:telemetry_prefix, [:eirinchan, :antispam_concurrency_repo])

    {:ok, repo_pid} = AntispamConcurrencyRepo.start_link(opts)
    Process.unlink(repo_pid)
    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    action = "race" <> suffix
    handler = {__MODULE__, make_ref()}
    uris = ["racea" <> suffix, "raceb" <> suffix]

    try do
      try do
        {:ok, first} =
          Boards.create_board(%{uri: hd(uris), title: "Race A"}, repo: AntispamConcurrencyRepo)

        {:ok, second} =
          Boards.create_board(%{uri: List.last(uris), title: "Race B"},
            repo: AntispamConcurrencyRepo
          )

        :ok =
          :telemetry.attach(
            handler,
            [:eirinchan, :antispam_concurrency_repo, :query],
            &__MODULE__.query_event/4,
            self()
          )

        config =
          Config.compose(nil, %{}, %{
            flood_time: 0,
            flood_global_count: 1,
            flood_global_window: 60,
            filters: []
          })

        parent = self()

        tasks =
          for {board, action_name} <- [{first, action}, {second, String.upcase(action)}] do
            Task.async(fn ->
              Process.put(:race_parent, parent)
              receive do: (:start -> :ok)

              reserve(kind, board, action_name, config)
            end)
          end

        Enum.each(tasks, &send(&1.pid, :start))
        assert_receive {:quota_read, first_pid}, 2_000
        second_pid = receive do: ({:quota_read, pid} -> pid), after: (150 -> nil)
        send(first_pid, :continue)

        if second_pid do
          send(second_pid, :continue)
        else
          assert_receive {:quota_read, later_pid}, 2_000
          send(later_pid, :continue)
        end

        results = Enum.map(tasks, &Task.await(&1, 5_000))
        assert Enum.count(results, &(&1 == :ok)) == 1
        assert Enum.count(results, &(&1 == {:error, :antispam})) == 1
      after
        :telemetry.detach(handler)

        board_ids =
          AntispamConcurrencyRepo.all(
            from board in BoardRecord, where: board.uri in ^uris, select: board.id
          )

        AntispamConcurrencyRepo.delete_all(
          from entry in FloodEntry, where: entry.board_id in ^board_ids
        )

        AntispamConcurrencyRepo.delete_all(
          from board in BoardRecord, where: board.id in ^board_ids
        )
      end
    after
      if Process.alive?(repo_pid), do: GenServer.stop(repo_pid)
    end
  end

  defp reserve(:public_action, board, action, config) do
    Antispam.reserve_public_action(board, action, %{}, %{remote_ip: {192, 0, 2, 7}}, config,
      repo: AntispamConcurrencyRepo
    )
  end

  defp reserve(:upload, board, _action, config) do
    request = %{remote_ip: {192, 0, 2, 7}}
    Antispam.reserve_upload_attempt(board, %{}, request, config, repo: AntispamConcurrencyRepo)
  end

  def query_event(_event, _measurements, metadata, _recipient) do
    query = String.downcase(Map.get(metadata, :query, ""))
    parent = Process.get(:race_parent)

    if parent && String.contains?(query, "count(") && String.contains?(query, "\"flood_entries\"") do
      send(parent, {:quota_read, self()})
      receive do: (:continue -> :ok), after: (2_000 -> raise "quota barrier timed out")
    end
  end
end
