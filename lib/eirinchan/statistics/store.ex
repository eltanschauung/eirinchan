defmodule Eirinchan.Statistics.Store do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.Boards
  alias Eirinchan.Repo
  alias Eirinchan.Statistics.Snapshot
  alias Eirinchan.Stats

  def add_counters(period_start, counters, opts \\ [])
      when is_integer(period_start) and is_map(counters) do
    repo = Keyword.get(opts, :repo, Repo)
    period_start = DateTime.from_unix!(period_start, :second)
    period_end = DateTime.add(period_start, 3_600, :second)

    repo.transaction(fn ->
      ensure_snapshot(repo, period_start, period_end)

      snapshot =
        repo.one!(
          from snapshot in Snapshot,
            where: snapshot.period_start == ^period_start,
            lock: "FOR UPDATE"
        )

      merged =
        Map.merge(snapshot.counters || %{}, counters, fn _key, left, right -> left + right end)

      snapshot
      |> Snapshot.changeset(%{counters: merged})
      |> repo.update!()

      :ok
    end)
    |> transaction_result()
  end

  def finalize(%DateTime{} = period_end, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    presence_server = Keyword.get(opts, :presence_server, Eirinchan.BrowserPresence)
    captured_at = Keyword.get(opts, :captured_at, DateTime.utc_now(:microsecond))
    daily? = Keyword.get(opts, :daily?, false)
    period_end = DateTime.truncate(period_end, :second)
    period_start = DateTime.add(period_end, -3_600, :second)
    board_ids = Boards.list_boards(repo: repo) |> Enum.map(& &1.id)

    attrs = %{
      captured_at: captured_at,
      posts_per_hour: Stats.posts_perhour(board_ids, now: period_end, repo: repo),
      threads_per_hour: Stats.threads_perhour(board_ids, now: period_end, repo: repo),
      users_10minutes:
        Stats.users_10minutes(now: period_end, repo: repo, server: presence_server),
      finalized: true
    }

    attrs =
      if daily? do
        Map.merge(attrs, %{
          daily_total_requests: requests_in_previous_24_hours(repo, period_end),
          daily_unique_visitors:
            Stats.users_24hours(
              now: period_end,
              repo: repo,
              server: presence_server
            )
        })
      else
        attrs
      end

    repo.transaction(fn ->
      ensure_snapshot(repo, period_start, period_end)

      snapshot =
        repo.one!(
          from snapshot in Snapshot,
            where: snapshot.period_start == ^period_start,
            lock: "FOR UPDATE"
        )

      snapshot
      |> Snapshot.changeset(attrs)
      |> repo.update!()
    end)
    |> transaction_result()
  end

  defp requests_in_previous_24_hours(repo, period_end) do
    cutoff = DateTime.add(period_end, -24 * 3_600, :second)

    repo.all(
      from snapshot in Snapshot,
        where: snapshot.period_start >= ^cutoff and snapshot.period_start < ^period_end,
        select: snapshot.counters
    )
    |> Enum.reduce(0, fn counters, total ->
      total + Map.get(counters || %{}, "requests.total", 0)
    end)
  end

  defp ensure_snapshot(repo, period_start, period_end) do
    %Snapshot{}
    |> Snapshot.changeset(%{
      period_start: period_start,
      period_end: period_end,
      counters: %{},
      finalized: false
    })
    |> repo.insert!(on_conflict: :nothing, conflict_target: :period_start)
  end

  defp transaction_result({:ok, result}), do: {:ok, result}
  defp transaction_result({:error, reason}), do: {:error, reason}
end
