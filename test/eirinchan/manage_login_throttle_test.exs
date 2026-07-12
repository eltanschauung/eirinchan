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
    Application.put_env(:eirinchan, :manage_login_throttle_max_entries, 3)
    config = %{mod_login_max_attempts: 100, mod_login_lockout_seconds: 60}

    assert :ok = ManageLoginThrottle.record_failure("first", {192, 0, 2, 1}, config)
    assert :ets.info(:eirinchan_manage_login_throttle, :size) == 3

    assert {:error, 60} =
             ManageLoginThrottle.record_failure("second", {192, 0, 2, 2}, config)

    assert :ets.info(:eirinchan_manage_login_throttle, :size) == 3
  end

  test "locks a username across distributed source addresses" do
    config = %{
      mod_login_max_attempts: 100,
      mod_login_ip_max_attempts: 100,
      mod_login_username_max_attempts: 2,
      mod_login_window_seconds: 300,
      mod_login_lockout_seconds: 60
    }

    assert :ok = ManageLoginThrottle.record_failure("admin", {192, 0, 2, 1}, config)

    assert {:error, 60} =
             ManageLoginThrottle.record_failure("admin", {198, 51, 100, 2}, config)

    assert {:error, retry_after} =
             ManageLoginThrottle.allowed?("admin", {203, 0, 113, 3}, config)

    assert retry_after > 0
  end
end
