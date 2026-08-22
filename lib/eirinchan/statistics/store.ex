defmodule Eirinchan.Statistics.Store do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.Boards
  alias Eirinchan.Repo
  alias Eirinchan.Statistics.SearchTerm
  alias Eirinchan.Statistics.Snapshot
  alias Eirinchan.Statistics.Week
  alias Eirinchan.Statistics.WeeklyVisitors
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
    add_batch(period_start, counters, %{}, opts)
  end

  def add_batch(period_start, counters, search_terms, opts \\ [])
      when is_integer(period_start) and is_map(counters) and is_map(search_terms) do
    repo = Keyword.get(opts, :repo, Repo)
    period_start = DateTime.from_unix!(period_start * 1_000_000, :microsecond)
    period_end = DateTime.add(period_start, 3_600, :second)

    repo.transaction(fn ->
      ensure_snapshot(repo, period_start, period_end)

      persist_counters(repo, period_start, counters)
      persist_search_terms(repo, period_start, search_terms)

      :ok
    end)
    |> transaction_result()
  end

  def finalize(%DateTime{} = period_end, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    presence_server = Keyword.get(opts, :presence_server, Eirinchan.BrowserPresence)
    captured_at = Keyword.get(opts, :captured_at, DateTime.utc_now(:microsecond))
    daily? = Keyword.get(opts, :daily?, false)
    weekly_start = Keyword.get(opts, :weekly_start)
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
          daily_board_ppd:
            board_ids
            |> Stats.posts_perday_by_board(now: period_end, repo: repo)
            |> stringify_keys(),
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

      attrs = weekly_attrs(attrs, snapshot, weekly_start, repo)

      updated_snapshot =
        snapshot
        |> Snapshot.changeset(attrs)
        |> repo.update!()

      if weekly_start, do: WeeklyVisitors.clear(repo, weekly_start)
      updated_snapshot
    end)
    |> transaction_result()
  end

  def latest_daily_board_ppd(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.one(
      from snapshot in Snapshot,
        where: snapshot.finalized and not is_nil(snapshot.daily_board_ppd),
        order_by: [desc: snapshot.period_end],
        limit: 1,
        select: snapshot.daily_board_ppd
    ) || %{}
  end

  def weekly_unique_visitor_rollups(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.all(
      from snapshot in Snapshot,
        where:
          snapshot.finalized and not is_nil(snapshot.weekly_period_start) and
            not is_nil(snapshot.weekly_unique_visitors),
        order_by: snapshot.weekly_period_start,
        select: {snapshot.weekly_period_start, snapshot.weekly_unique_visitors}
    )
    |> Enum.map(fn {week_start, unique_visitors} ->
      %{
        week_start: week_start,
        week_end: Week.end_at(week_start),
        unique_visitors: unique_visitors
      }
    end)
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

  defp weekly_attrs(attrs, _snapshot, nil, _repo), do: attrs

  defp weekly_attrs(attrs, snapshot, weekly_start, repo) do
    unique_visitors =
      if is_integer(snapshot.weekly_unique_visitors),
        do: snapshot.weekly_unique_visitors,
        else: WeeklyVisitors.count(repo, weekly_start)

    Map.merge(attrs, %{
      weekly_period_start: weekly_start,
      weekly_unique_visitors: unique_visitors
    })
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
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

  defp persist_counters(_repo, _period_start, counters) when map_size(counters) == 0, do: :ok

  defp persist_counters(repo, period_start, counters) do
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
  end

  defp persist_search_terms(_repo, _period_start, search_terms)
       when map_size(search_terms) == 0,
       do: :ok

  defp persist_search_terms(repo, period_start, search_terms) do
    now = DateTime.utc_now(:microsecond)

    Enum.each(search_terms, fn
      {{field, term}, count}
      when is_binary(field) and is_binary(term) and is_integer(count) and count > 0 ->
        repo.insert_all(
          SearchTerm,
          [
            %{
              period_start: period_start,
              field: field,
              term: term,
              occurrences: count,
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: [inc: [occurrences: count], set: [updated_at: now]],
          conflict_target: [:period_start, :field, :term]
        )

      _invalid ->
        :ok
    end)
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
