defmodule Eirinchan.Statistics.WeeklyVisitors do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.Repo
  alias Eirinchan.Statistics.Week
  alias Eirinchan.Statistics.WeeklyVisitor

  def record!(repo, entries) when is_list(entries) do
    inserted_at = DateTime.utc_now(:microsecond)

    rows =
      entries
      |> Enum.map(fn {browser_ref, seen_at} ->
        %{
          week_start: seen_at |> DateTime.from_unix!(:second) |> Week.start_at(),
          browser_ref: browser_ref,
          inserted_at: inserted_at
        }
      end)
      |> Enum.uniq_by(&{&1.week_start, &1.browser_ref})

    repo.insert_all(WeeklyVisitor, rows,
      on_conflict: :nothing,
      conflict_target: [:week_start, :browser_ref]
    )
  end

  def backfill_current_week(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)
    week_start = Week.start_at(now)
    inserted_at = DateTime.utc_now(:microsecond)

    query =
      from identity in Identity,
        where: identity.presence_seen_at >= ^week_start and identity.presence_seen_at <= ^now,
        select: %{
          week_start: ^week_start,
          browser_ref: identity.browser_ref,
          inserted_at: ^inserted_at
        }

    repo.insert_all(WeeklyVisitor, query,
      on_conflict: :nothing,
      conflict_target: [:week_start, :browser_ref]
    )
  rescue
    error -> {:error, error}
  end

  def count(repo, %DateTime{} = week_start) do
    repo.aggregate(
      from(visitor in WeeklyVisitor, where: visitor.week_start == ^week_start),
      :count,
      :browser_ref
    ) || 0
  end

  def pending_completed_week_start(repo, %DateTime{} = period_end) do
    current_week_start = Week.start_at(period_end)

    repo.one(
      from visitor in WeeklyVisitor,
        where: visitor.week_start < ^current_week_start,
        order_by: [asc: visitor.week_start],
        limit: 1,
        select: visitor.week_start
    )
  end

  def clear(repo, %DateTime{} = week_start) do
    repo.delete_all(from visitor in WeeklyVisitor, where: visitor.week_start == ^week_start)
  end
end
