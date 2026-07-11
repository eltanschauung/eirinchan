defmodule Eirinchan.BrowserPresenceTest do
  use ExUnit.Case, async: false

  alias Eirinchan.BrowserPresence

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
    original_max = Application.get_env(:eirinchan, :browser_presence_max_entries)

    on_exit(fn ->
      Application.put_env(:eirinchan, :browser_presence_max_entries, original_max)
    end)

    :ok
  end

  test "users_10minutes counts only recent unique browser tokens" do
    now = System.system_time(:second)

    true = :ets.insert(:eirinchan_browser_presence, {"token-1234567890123456", now})
    true = :ets.insert(:eirinchan_browser_presence, {"token-abcdefghijklmnop", now - 60})
    true = :ets.insert(:eirinchan_browser_presence, {"token-stale-1234567890", now - 601})

    assert BrowserPresence.users_10minutes() == 2
  end

  test "touch updates valid browser tokens" do
    assert BrowserPresence.touch("token-1234567890123456") == :ok
    assert [{"token-1234567890123456", _seen_at}] = :ets.lookup(:eirinchan_browser_presence, "token-1234567890123456")
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
end
