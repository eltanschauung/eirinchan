defmodule Eirinchan.Statistics.WeeklyVisitorsTest do
  use Eirinchan.DataCase

  alias Eirinchan.BrowserIdentities
  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Repo
  alias Eirinchan.Statistics.Week
  alias Eirinchan.Statistics.WeeklyVisitor
  alias Eirinchan.Statistics.WeeklyVisitors

  test "backfills the current week from durable crawler-filtered presence" do
    now = ~U[2026-08-22 12:00:00Z]
    week_start = Week.start_at(now)
    current = identity_fixture(DateTime.add(week_start, 3_600, :second))
    _older = identity_fixture(DateTime.add(week_start, -1, :second))
    _never_present = identity_fixture(nil)

    assert {1, nil} = WeeklyVisitors.backfill_current_week(repo: Repo, now: now)

    assert Repo.get_by!(WeeklyVisitor,
             week_start: week_start,
             browser_ref: current.browser_ref
           )

    assert Repo.aggregate(WeeklyVisitor, :count, :browser_ref) == 1
  end

  defp identity_fixture(presence_seen_at) do
    now = DateTime.utc_now(:second)

    %Identity{}
    |> Identity.changeset(%{
      browser_ref: BrowserIdentity.generate_token() |> BrowserIdentity.reference(),
      issued_at: now,
      last_seen_at: now,
      presence_seen_at: presence_seen_at,
      expires_at: DateTime.add(now, BrowserIdentities.ttl_seconds(), :second)
    })
    |> Repo.insert!()
  end
end
