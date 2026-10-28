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

  test "a one-attempt limit locks immediately after an expired window" do
    ip = {192, 0, 2, 1}
    config = %{max_attempts: 1, global_max_attempts: 100, window_seconds: 1, lockout_seconds: 60}
    assert {:error, 60} = IpAccessAuthThrottle.record_failure(ip, config)
    {:ok, subnet} = Eirinchan.IpAccessAuth.subnet_for_ip(ip)
    key = {:subnet, subnet}
    [entry] = :ets.lookup(:eirinchan_ip_access_auth_throttle, key)

    :ets.insert(
      :eirinchan_ip_access_auth_throttle,
      entry |> put_elem(2, System.system_time(:second) - 2) |> put_elem(3, 0)
    )

    assert {:error, 60} = IpAccessAuthThrottle.record_failure(ip, config)
  end

  test "long configured windows survive the hourly pruning threshold" do
    ip = {192, 0, 2, 1}

    config = %{
      max_attempts: 100,
      global_max_attempts: 100,
      window_seconds: 7_200,
      lockout_seconds: 60
    }

    assert :ok = IpAccessAuthThrottle.record_failure(ip, config)
    {:ok, subnet} = Eirinchan.IpAccessAuth.subnet_for_ip(ip)
    key = {:subnet, subnet}
    now = System.system_time(:second)
    [entry] = :ets.lookup(:eirinchan_ip_access_auth_throttle, key)
    entry = entry |> put_elem(2, now - 4_000) |> put_elem(3, 0)
    entry = if tuple_size(entry) == 5, do: put_elem(entry, 4, now + 3_200), else: entry
    :ets.insert(:eirinchan_ip_access_auth_throttle, entry)
    send(Process.whereis(IpAccessAuthThrottle), :prune)
    :sys.get_state(IpAccessAuthThrottle)
    assert :ets.member(:eirinchan_ip_access_auth_throttle, key)
  end

  test "simultaneous failures are all counted" do
    ip = {192, 0, 2, 1}

    config = %{
      max_attempts: 1_000,
      global_max_attempts: 1_000,
      window_seconds: 300,
      lockout_seconds: 60
    }

    1..200
    |> Task.async_stream(fn _ -> IpAccessAuthThrottle.record_failure(ip, config) end,
      max_concurrency: 100
    )
    |> Enum.each(fn result -> assert result == {:ok, :ok} end)

    [entry] = :ets.lookup(:eirinchan_ip_access_auth_throttle, :global)
    assert elem(entry, 1) == 200
  end
end
