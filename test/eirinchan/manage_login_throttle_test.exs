defmodule Eirinchan.ManageLoginThrottleTest do
  use ExUnit.Case, async: false

  alias Eirinchan.ManageLoginThrottle

  setup do
    :ets.delete_all_objects(:eirinchan_manage_login_throttle)
    original_max = Application.get_env(:eirinchan, :manage_login_throttle_max_entries)

    on_exit(fn ->
      Application.put_env(:eirinchan, :manage_login_throttle_max_entries, original_max)
      :ets.delete_all_objects(:eirinchan_manage_login_throttle)
    end)

    :ok
  end

  test "refuses new throttle identities after the bounded table is full" do
    Application.put_env(:eirinchan, :manage_login_throttle_max_entries, 2)
    config = %{mod_login_max_attempts: 100, mod_login_lockout_seconds: 60}

    assert :ok = ManageLoginThrottle.record_failure("first", {192, 0, 2, 1}, config)
    assert :ets.info(:eirinchan_manage_login_throttle, :size) == 2

    assert {:error, 60} =
             ManageLoginThrottle.record_failure("second", {192, 0, 2, 2}, config)

    assert :ets.info(:eirinchan_manage_login_throttle, :size) == 2
  end
end
