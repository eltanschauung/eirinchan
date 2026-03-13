defmodule EirinchanWeb.FragmentCacheTest do
  use ExUnit.Case, async: false

  alias EirinchanWeb.FragmentCache

  setup do
    FragmentCache.clear()
    :ok
  end

  test "fetch_or_store caches values" do
    assert FragmentCache.fetch_or_store(:alpha, fn -> "one" end) == "one"
    assert FragmentCache.fetch_or_store(:alpha, fn -> "two" end) == "one"
  end

  test "cache recovers after the owner process restarts" do
    assert FragmentCache.fetch_or_store(:alpha, fn -> "one" end) == "one"

    old_pid = Process.whereis(FragmentCache)
    ref = Process.monitor(old_pid)
    GenServer.stop(old_pid, :normal)
    assert_receive {:DOWN, ^ref, :process, ^old_pid, :normal}

    new_pid = wait_for_restart(old_pid)
    assert is_pid(new_pid)
    refute new_pid == old_pid

    assert FragmentCache.fetch_or_store(:beta, fn -> "two" end) == "two"
  end

  defp wait_for_restart(old_pid, attempts \\ 20)

  defp wait_for_restart(_old_pid, 0), do: Process.whereis(FragmentCache)

  defp wait_for_restart(old_pid, attempts) do
    case Process.whereis(FragmentCache) do
      pid when is_pid(pid) and pid != old_pid ->
        pid

      _ ->
        Process.sleep(25)
        wait_for_restart(old_pid, attempts - 1)
    end
  end
end
