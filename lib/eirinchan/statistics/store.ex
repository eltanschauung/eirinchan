defmodule Eirinchan.Statistics.Store do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.Boards
  alias Eirinchan.Repo
  alias Eirinchan.Statistics.Snapshot
  alias Eirinchan.Stats

  @search_identity_limits [
    {"search.clients.network.", 50},
    {"search.clients.user_agent.", 50},
    {"search.clients.combined.", 50},
    {"search.client_features.network.", 100},
    {"search.client_features.user_agent.", 100},
    {"search.client_features.combined.", 100}
  ]

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
        snapshot.counters
        |> Kernel.||(%{})
        |> Map.merge(counters, fn _key, left, right -> left + right end)
        |> bound_search_identity_counters()

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

  defp bound_search_identity_counters(counters) do
    Enum.reduce(@search_identity_limits, counters, fn {prefix, limit}, bounded ->
      overflow_key = prefix <> "other"

      entries =
        bounded
        |> Enum.filter(fn {key, _count} ->
          String.starts_with?(key, prefix) and key != overflow_key
        end)
        |> Enum.sort_by(fn {key, count} -> {-count, key} end)

      {_kept, discarded} = Enum.split(entries, limit)

      discarded_count =
        Enum.reduce(discarded, Map.get(bounded, overflow_key, 0), fn {_key, count}, total ->
          total + count
        end)

      bounded = Map.drop(bounded, Enum.map(discarded, &elem(&1, 0)))

      if discarded_count > 0,
        do: Map.put(bounded, overflow_key, discarded_count),
        else: Map.delete(bounded, overflow_key)
    end)
  end

  defp transaction_result({:ok, result}), do: {:ok, result}
  defp transaction_result({:error, reason}), do: {:error, reason}
end
