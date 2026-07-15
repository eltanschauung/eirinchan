defmodule Eirinchan.BrowserPresenceTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.BrowserIdentities
  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.BrowserPresence
  alias Eirinchan.Repo

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
    :ets.delete_all_objects(:eirinchan_browser_presence_dirty)
    original_max = Application.get_env(:eirinchan, :browser_presence_max_entries)

    on_exit(fn ->
      Application.put_env(:eirinchan, :browser_presence_max_entries, original_max)
    end)

    :ok
  end

  test "users_10minutes counts only recently persisted browser presence" do
    now = DateTime.utc_now(:second)
    _recent = identity_fixture(now)
    _also_recent = identity_fixture(DateTime.add(now, -60, :second))
    _stale = identity_fixture(DateTime.add(now, -601, :second))
    _never_present = identity_fixture(nil)

    assert BrowserPresence.active_browsers_10minutes(now: now) == 2
    assert BrowserPresence.users_10minutes(now: now) == 2
  end

  test "touch batches durable presence that survives the ETS cache being cleared" do
    identity = identity_fixture(nil)

    assert :ok = BrowserPresence.touch(identity.browser_ref)
    assert :ok = BrowserPresence.flush()
    assert Repo.get!(Identity, identity.browser_ref).presence_seen_at

    :ets.delete_all_objects(:eirinchan_browser_presence)
    :ets.delete_all_objects(:eirinchan_browser_presence_dirty)

    assert BrowserPresence.users_10minutes() == 1
  end

  test "touch updates valid browser references" do
    assert BrowserPresence.touch("token-1234567890123456") == :ok

    assert [{"token-1234567890123456", _seen_at}] =
             :ets.lookup(:eirinchan_browser_presence, "token-1234567890123456")
  end

  test "touch bounds new identities while continuing to refresh known identities" do
    Application.put_env(:eirinchan, :browser_presence_max_entries, 2)

    assert :ok = BrowserPresence.touch("token-1234567890123456")
    assert :ok = BrowserPresence.touch("token-abcdefghijklmnop")
    assert :ok = BrowserPresence.touch("token-over-cap-123456789")
    assert :ets.info(:eirinchan_browser_presence, :size) == 2

    old_seen_at = System.system_time(:second) - 60
    true = :ets.insert(:eirinchan_browser_presence, {"token-1234567890123456", old_seen_at})
    assert :ok = BrowserPresence.touch("token-1234567890123456")

    assert [{"token-1234567890123456", refreshed_at}] =
             :ets.lookup(:eirinchan_browser_presence, "token-1234567890123456")

    assert refreshed_at > old_seen_at
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
