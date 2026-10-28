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

  test "a one-attempt limit locks on the first failure" do
    config = %{mod_login_max_attempts: 1, mod_login_lockout_seconds: 60}
    assert {:error, 60} = ManageLoginThrottle.record_failure("admin", {192, 0, 2, 1}, config)
  end

  test "in-flight authentication consumes the remaining attempt and is released on exit" do
    config = %{mod_login_max_attempts: 1, mod_login_lockout_seconds: 60}
    ip = {192, 0, 2, 1}
    parent = self()

    task =
      Task.async(fn ->
        assert {:ok, lease} = ManageLoginThrottle.acquire("admin", ip, config)
        send(parent, :acquired)
        receive do: (:release -> ManageLoginThrottle.release(lease))
      end)

    assert_receive :acquired, 1_000
    assert {:error, 1} = ManageLoginThrottle.acquire("admin", ip, config)
    send(task.pid, :release)
    assert :ok = Task.await(task)
    assert {:ok, lease} = ManageLoginThrottle.acquire("admin", ip, config)
    assert :ok = ManageLoginThrottle.release(lease)
  end

  test "a crashed authentication process cannot strand its reservation" do
    config = %{mod_login_max_attempts: 1}
    ip = {192, 0, 2, 1}
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        assert {:ok, _lease} = ManageLoginThrottle.acquire("admin", ip, config)
        send(parent, :acquired)
        receive do: (:stop -> exit(:synthetic))
      end)

    assert_receive :acquired, 1_000
    assert {:error, 1} = ManageLoginThrottle.acquire("admin", ip, config)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, :synthetic}, 1_000
    lease = wait_for_admission("admin", ip, config, 100)
    assert :ok = ManageLoginThrottle.release(lease)
  end

  test "a partial failure window leaves only its remaining parallel capacity" do
    config = %{mod_login_max_attempts: 2, mod_login_lockout_seconds: 60}
    ip = {192, 0, 2, 1}
    assert :ok = ManageLoginThrottle.record_failure("admin", ip, config)
    assert {:ok, lease} = ManageLoginThrottle.acquire("admin", ip, config)
    assert {:error, 1} = ManageLoginThrottle.acquire("admin", ip, config)
    assert {:error, 60} = ManageLoginThrottle.record_failure("admin", ip, config)
    assert :ok = ManageLoginThrottle.release(lease)
    assert {:error, _} = ManageLoginThrottle.acquire("admin", ip, config)
  end

  test "another process cannot release a live caller's reservation" do
    config = %{mod_login_max_attempts: 1}
    ip = {192, 0, 2, 1}
    assert {:ok, lease} = ManageLoginThrottle.acquire("admin", ip, config)
    assert :ok = Task.async(fn -> ManageLoginThrottle.release(lease) end) |> Task.await()
    assert {:error, 1} = ManageLoginThrottle.acquire("admin", ip, config)
    assert :ok = ManageLoginThrottle.release(lease)
  end

  test "concurrent authentication state is bounded across distinct identities" do
    config = %{mod_login_max_attempts: 5}

    leases =
      for index <- 1..8 do
        {:ok, lease} = ManageLoginThrottle.acquire("user#{index}", {192, 0, 2, index}, config)
        lease
      end

    try do
      assert {:error, 1} = ManageLoginThrottle.acquire("additional", {198, 51, 100, 1}, config)
    after
      Enum.each(leases, &ManageLoginThrottle.release/1)
    end
  end

  defp wait_for_admission(_username, _ip, _config, 0), do: flunk("lease cleanup timed out")

  defp wait_for_admission(username, ip, config, attempts) do
    case ManageLoginThrottle.acquire(username, ip, config) do
      {:ok, lease} ->
        lease

      {:error, 1} ->
        Process.sleep(5)
        wait_for_admission(username, ip, config, attempts - 1)
    end
  end

  test "numeric string settings do not crash the throttle owner" do
    owner = Process.whereis(ManageLoginThrottle)

    config = %{
      mod_login_max_attempts: "1",
      mod_login_window_seconds: "300",
      mod_login_lockout_seconds: "60"
    }

    assert {:error, 60} = ManageLoginThrottle.record_failure("admin", {192, 0, 2, 1}, config)
    assert Process.whereis(ManageLoginThrottle) == owner
  end

  test "legacy pruning preserves the configured long window" do
    now = System.system_time(:second)
    :ets.insert(:eirinchan_manage_login_throttle, {{:username, "partial"}, 1, now - 4_000, 0})
    :ets.insert(:eirinchan_manage_login_throttle, {{:username, "expired"}, 1, now - 8_000, 0})

    assert :ok =
             ManageLoginThrottle.allowed?("other", {192, 0, 2, 1}, %{
               mod_login_window_seconds: 7_200
             })

    send(Process.whereis(ManageLoginThrottle), :prune)
    :sys.get_state(ManageLoginThrottle)
    assert :ets.member(:eirinchan_manage_login_throttle, {:username, "partial"})
    refute :ets.member(:eirinchan_manage_login_throttle, {:username, "expired"})
  end

  test "simultaneous failures are all counted per username" do
    config = %{
      mod_login_max_attempts: 1_000,
      mod_login_username_max_attempts: 1_000,
      mod_login_ip_max_attempts: 1_000
    }

    1..200
    |> Task.async_stream(
      fn _ -> ManageLoginThrottle.record_failure("admin", {192, 0, 2, 1}, config) end,
      max_concurrency: 100
    )
    |> Enum.each(fn result -> assert result == {:ok, :ok} end)

    [entry] = :ets.lookup(:eirinchan_manage_login_throttle, {:username, "admin"})
    assert elem(entry, 1) == 200
  end
end
