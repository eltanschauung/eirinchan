defmodule Eirinchan.Statistics.WorkerTest do
  use Eirinchan.DataCase

  alias Eirinchan.BrowserIdentities
  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Repo
  alias Eirinchan.Statistics
  alias Eirinchan.Statistics.Snapshot
  alias Eirinchan.Statistics.Store
  alias Eirinchan.Statistics.Worker

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
    :ets.delete_all_objects(:eirinchan_browser_presence_dirty)

    worker =
      start_supervised!(
        {Worker,
         name: nil,
         repo: Repo,
         flush_interval_ms: false,
         schedule_snapshots?: false,
         enabled?: fn -> true end,
         local_hour: fn _datetime -> 0 end}
      )

    %{worker: worker}
  end

  test "batches request counters and finalizes hourly and daily values", %{worker: worker} do
    period_end = ~U[2026-07-18 12:00:00Z]
    request_time = DateTime.add(period_end, -30 * 60, :second)
    board = board_fixture()
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread)

    Repo.update_all(
      Ecto.Query.from(post in Eirinchan.Posts.Post, where: post.id in ^[thread.id, reply.id]),
      set: [inserted_at: request_time]
    )

    identity = identity_fixture(period_end)
    assert identity.presence_seen_at == DateTime.add(period_end, -60, :second)

    Statistics.record_metrics(
      ["requests.total", "requests.board.test.index.full", "actions.search.attempted"],
      request_time
    )

    assert :ok = Worker.flush(worker)
    assert :ok = Worker.finalize(worker, period_end)

    snapshot = Repo.get_by!(Snapshot, period_start: DateTime.add(period_end, -3_600, :second))

    assert snapshot.finalized
    assert snapshot.posts_per_hour == 2
    assert snapshot.threads_per_hour == 1
    assert snapshot.users_10minutes == 1
    assert snapshot.counters["requests.total"] == 1
    assert snapshot.counters["requests.board.test.index.full"] == 1
    assert snapshot.daily_total_requests == 1
    assert snapshot.daily_unique_visitors == 1
  end

  test "restores a drained batch after a persistence failure" do
    now = ~U[2026-07-18 12:30:00Z]
    Statistics.record_metrics(["requests.total"], now)
    drained = Statistics.drain_counters()
    bucket = Statistics.hour_start_unix(now)

    assert drained == %{bucket => %{"requests.total" => 1}}
    assert Statistics.drain_counters() == %{}

    Statistics.restore_counters(bucket, drained[bucket])
    assert Statistics.drain_counters() == drained
  end

  test "bounds persisted pseudonymous search identities" do
    period_start = ~U[2026-07-18 12:00:00Z]
    bucket = DateTime.to_unix(period_start, :second)

    counters =
      Map.new(1..60, fn number ->
        {"search.clients.network.client#{number}", number}
      end)

    assert {:ok, :ok} = Store.add_counters(bucket, counters, repo: Repo)

    snapshot = Repo.get_by!(Snapshot, period_start: period_start)

    retained =
      Enum.filter(snapshot.counters, fn {key, _count} ->
        String.starts_with?(key, "search.clients.network.")
      end)

    assert length(retained) == 51
    assert snapshot.counters["search.clients.network.client60"] == 60
    assert snapshot.counters["search.clients.network.other"] == Enum.sum(1..10)
  end

  defp identity_fixture(now) do
    %Identity{}
    |> Identity.changeset(%{
      browser_ref: BrowserIdentity.generate_token() |> BrowserIdentity.reference(),
      issued_at: DateTime.add(now, -60, :second),
      last_seen_at: DateTime.add(now, -60, :second),
      presence_seen_at: DateTime.add(now, -60, :second),
      expires_at: DateTime.add(now, BrowserIdentities.ttl_seconds(), :second)
    })
    |> Repo.insert!()
  end
end
