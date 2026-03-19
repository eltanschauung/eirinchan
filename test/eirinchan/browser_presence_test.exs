defmodule Eirinchan.BrowserPresenceTest do
  use ExUnit.Case, async: false

  alias Eirinchan.BrowserPresence

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
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
end
