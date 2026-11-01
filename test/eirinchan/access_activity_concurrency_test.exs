defmodule Eirinchan.AccessActivityRepo do
  use Ecto.Repo, otp_app: :eirinchan, adapter: Ecto.Adapters.Postgres
end

defmodule Eirinchan.AccessActivityConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Eirinchan.{AccessActivityRepo, AccessList, IpAccessEntry, Repo}

  test "independent concurrent authentications preserve age/count and cap distinct agents" do
    opts = Repo.config()
    assert Keyword.get(opts, :hostname) in ["localhost", "127.0.0.1", "::1"]
    assert Regex.match?(~r/_test[0-9]*$/, Keyword.get(opts, :database, ""))
    opts = opts |> Keyword.put(:pool, DBConnection.ConnectionPool) |> Keyword.put(:pool_size, 4)
    {:ok, pid} = AccessActivityRepo.start_link(opts)
    Process.unlink(pid)
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    <<a::binary-size(4), b::binary-size(4)>> = suffix
    ip = "2001:db8:#{a}:#{b}::1/128"

    try do
      assert {:ok, first} =
               AccessList.record_access(ip, "synthetic-door", repo: AccessActivityRepo)

      AccessActivityRepo.update_all(from(e in IpAccessEntry, where: e.ip == ^ip),
        set: [post_count: 3]
      )

      parent = self()

      tasks =
        for n <- 1..8 do
          Task.async(fn ->
            :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
            send(parent, {:ready, self()})
            receive do: (:start -> :ok)

            AccessList.record_access(ip, "synthetic-door",
              repo: AccessActivityRepo,
              user_agent: "Synthetic/#{n}"
            )
          end)
        end

      for _ <- tasks, do: assert_receive({:ready, _}, 3_000)
      Enum.each(tasks, &send(&1.pid, :start))
      for task <- tasks, do: assert({:ok, _} = Task.await(task, 15_000))

      for n <- 9..12,
          do:
            AccessList.record_access(ip, "synthetic-door",
              repo: AccessActivityRepo,
              user_agent: "Synthetic/#{n}"
            )

      final = AccessActivityRepo.get!(IpAccessEntry, ip)
      assert final.authenticated_at == first.authenticated_at
      assert final.post_count == 3
      assert length(final.user_agents) == 10
      assert Enum.uniq(final.user_agents) == final.user_agents
    after
      AccessActivityRepo.delete_all(from e in IpAccessEntry, where: e.ip == ^ip)
      if Process.alive?(pid), do: GenServer.stop(pid)
    end
  end
end
