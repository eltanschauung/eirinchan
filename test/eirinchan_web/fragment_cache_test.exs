defmodule EirinchanWeb.FragmentCacheTest do
  use ExUnit.Case, async: false

  alias EirinchanWeb.FragmentCache

  setup do
    original = Application.get_env(:eirinchan, :fragment_cache)
    FragmentCache.clear()

    on_exit(fn ->
      Application.put_env(:eirinchan, :fragment_cache, original)
      FragmentCache.clear()
    end)

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

  test "expires cached values after the configured ttl" do
    Application.put_env(:eirinchan, :fragment_cache, max_entries: 10, ttl_ms: 10)

    assert FragmentCache.fetch_or_store(:expiring, fn -> "one" end) == "one"
    Process.sleep(20)
    assert FragmentCache.fetch_or_store(:expiring, fn -> "two" end) == "two"
  end

  test "evicts oldest entries at the configured size limit" do
    Application.put_env(:eirinchan, :fragment_cache, max_entries: 2, ttl_ms: 60_000)

    assert FragmentCache.fetch_or_store(:first, fn -> 1 end) == 1
    Process.sleep(2)
    assert FragmentCache.fetch_or_store(:second, fn -> 2 end) == 2
    Process.sleep(2)
    assert FragmentCache.fetch_or_store(:third, fn -> 3 end) == 3

    assert FragmentCache.size() == 2
    assert FragmentCache.fetch_or_store(:first, fn -> :recomputed end) == :recomputed
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
