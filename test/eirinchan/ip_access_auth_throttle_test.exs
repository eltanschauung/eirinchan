defmodule Eirinchan.IpAccessAuthThrottleTest do
  use ExUnit.Case, async: false

  alias Eirinchan.IpAccessAuthThrottle

  setup do
    :ets.delete_all_objects(:eirinchan_ip_access_auth_throttle)
    on_exit(fn -> :ets.delete_all_objects(:eirinchan_ip_access_auth_throttle) end)
    :ok
  end

  test "limits failures across subnets globally" do
    config = %{
      max_attempts: 100,
      global_max_attempts: 2,
      window_seconds: 300,
      lockout_seconds: 60
    }

    assert :ok = IpAccessAuthThrottle.record_failure({192, 0, 2, 1}, config)
    assert {:error, 60} = IpAccessAuthThrottle.record_failure({198, 51, 100, 1}, config)
    assert {:error, retry_after} = IpAccessAuthThrottle.allowed?({203, 0, 113, 1}, config)
    assert retry_after > 0
  end

  test "successful authentication only clears the source subnet lock" do
    config = %{
      max_attempts: 1,
      global_max_attempts: 100,
      window_seconds: 300,
      lockout_seconds: 60
    }

    assert {:error, 60} = IpAccessAuthThrottle.record_failure({192, 0, 2, 1}, config)
    assert {:error, _retry_after} = IpAccessAuthThrottle.allowed?({192, 0, 2, 99}, config)

    assert :ok = IpAccessAuthThrottle.clear({192, 0, 2, 10})
    assert :ok = IpAccessAuthThrottle.allowed?({192, 0, 2, 99}, config)
  end
end
