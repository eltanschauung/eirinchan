defmodule Eirinchan.PollsConcurrencyRepo do
  use Ecto.Repo, otp_app: :eirinchan, adapter: Ecto.Adapters.Postgres
end

defmodule Eirinchan.PollsConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Eirinchan.{Boards, BrowserIdentity, Polls, PollsConcurrencyRepo, Repo}
  alias Eirinchan.Posts.{Persistence, Post}
  alias Eirinchan.Runtime.Config

  test "concurrent creations on different boards share one two-per-hour allowance" do
    with_repo(fn boards, request ->
      parent = self()

      tasks =
        Enum.with_index(boards)
        |> Enum.map(fn {board, n} ->
          Task.async(fn ->
            send(parent, {:ready, self()})
            receive do: (:start -> :ok)

            {:ok, attrs} =
              Polls.attach(%{"body" => "/poll Q#{n} a b", "ip_subnet" => "192.0.2.240"})

            # Model the already-admitted upload path: it does not take the text
            # post flood lock. Poll admission must supply its own cross-board lock.
            Persistence.create_post_record(
              board,
              nil,
              attrs,
              request,
              PollsConcurrencyRepo,
              config(),
              DateTime.utc_now(),
              true,
              fn -> :ok end
            )
          end)
        end)

      for _ <- tasks, do: assert_receive({:ready, _}, 2_000)
      Enum.each(tasks, &send(&1.pid, :start))
      results = Enum.map(tasks, &Task.await(&1, 5_000))
      assert Enum.count(results, &match?({:ok, %Post{}}, &1)) == 2
      assert Enum.count(results, &(&1 == {:error, :poll_rate_limited})) == 1
      ids = Enum.map(boards, & &1.id)

      assert PollsConcurrencyRepo.aggregate(from(p in Post, where: p.board_id in ^ids), :count) ==
               2
    end)
  end

  test "simultaneous duplicate votes are idempotent, including competing choices" do
    with_repo(fn [board | _], request ->
      {:ok, attrs} = Polls.attach(%{"body" => "/poll Q a b c", "ip_subnet" => "192.0.2.240"})

      {:ok, post} =
        Persistence.create_post_record(
          board,
          nil,
          attrs,
          request,
          PollsConcurrencyRepo,
          config(),
          DateTime.utc_now(),
          true,
          fn -> :ok end
        )

      parent = self()

      tasks =
        for choice <- 0..2 do
          Task.async(fn ->
            send(parent, {:ready, self()})
            receive do: (:start -> :ok)
            Polls.vote(post.id, choice, request, repo: PollsConcurrencyRepo)
          end)
        end

      for _ <- tasks, do: assert_receive({:ready, _}, 2_000)
      Enum.each(tasks, &send(&1.pid, :start))
      for task <- tasks, do: assert({:ok, %{voted: true, total: 1}} = Task.await(task, 5_000))

      assert PollsConcurrencyRepo.aggregate(
               from(v in Eirinchan.Polls.Vote, where: v.post_id == ^post.id),
               :count
             ) == 1
    end)
  end

  defp config,
    do:
      Config.compose(nil, %{}, %{generation_strategy: "build_on_load", flood_time: 0, filters: []})

  defp with_repo(fun) do
    opts = Repo.config()
    assert Keyword.get(opts, :hostname) in ["localhost", "127.0.0.1", "::1"]
    assert Regex.match?(~r/_test[0-9]*$/, Keyword.get(opts, :database, ""))

    opts =
      opts
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 4)
      |> Keyword.put(:telemetry_prefix, [:eirinchan, :polls_concurrency])

    {:ok, pid} = PollsConcurrencyRepo.start_link(opts)
    Process.unlink(pid)
    suffix = Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    uris = Enum.map(1..3, &"pollrace#{&1}#{suffix}")
    ref = BrowserIdentity.reference("poll-race-#{suffix}")
    request = %{remote_ip: {192, 0, 2, 240}, browser_ref: ref}

    try do
      boards =
        Enum.map(uris, fn uri ->
          {:ok, board} =
            Boards.create_board(%{uri: uri, title: "Synthetic poll race"},
              repo: PollsConcurrencyRepo
            )

          board
        end)

      fun.(boards, request)
    after
      PollsConcurrencyRepo.delete_all(
        from q in Eirinchan.Antispam.SearchQuery, where: q.browser_ref == ^ref
      )

      PollsConcurrencyRepo.delete_all(
        from s in Eirinchan.BrowserAbuse.Signal, where: s.browser_ref == ^ref
      )

      PollsConcurrencyRepo.delete_all(
        from b in Eirinchan.Boards.BoardRecord, where: b.uri in ^uris
      )

      GenServer.stop(pid)
    end
  end
end
