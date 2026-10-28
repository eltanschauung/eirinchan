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

  test "deletes only entries in the requested tuple namespace" do
    assert FragmentCache.fetch_or_store({:announcement, :first}, fn -> "old" end) == "old"
    assert FragmentCache.fetch_or_store({:other, :first}, fn -> "kept" end) == "kept"
    assert FragmentCache.fetch_or_store(:plain, fn -> "plain" end) == "plain"

    assert :ok = FragmentCache.delete_namespace(:announcement)

    assert FragmentCache.fetch_or_store({:announcement, :first}, fn -> "new" end) == "new"
    assert FragmentCache.fetch_or_store({:other, :first}, fn -> "changed" end) == "kept"
    assert FragmentCache.fetch_or_store(:plain, fn -> "changed" end) == "plain"
  end

  test "deletes several tuple namespaces in one pass" do
    assert FragmentCache.fetch_or_store({:first, 1}, fn -> :old end) == :old
    assert FragmentCache.fetch_or_store({:second, 1}, fn -> :old end) == :old
    assert FragmentCache.fetch_or_store({:other, 1}, fn -> :kept end) == :kept

    assert :ok = FragmentCache.delete_namespaces([:first, :second])

    assert FragmentCache.fetch_or_store({:first, 1}, fn -> :new end) == :new
    assert FragmentCache.fetch_or_store({:second, 1}, fn -> :new end) == :new
    assert FragmentCache.fetch_or_store({:other, 1}, fn -> :changed end) == :kept
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

  test "an in-flight fill cannot repopulate after a full invalidation" do
    task = blocked_fill({:board, 1})
    assert :ok = FragmentCache.clear()
    send(task.pid, :finish_fill)
    assert Task.await(task) == :old
    assert FragmentCache.fetch_or_store({:board, 1}, fn -> :new end) == :new
  end

  test "an in-flight fill cannot repopulate an invalidated namespace" do
    task = blocked_fill({:board, 1})
    assert :ok = FragmentCache.delete_namespace(:board)
    send(task.pid, :finish_fill)
    assert Task.await(task) == :old
    assert FragmentCache.fetch_or_store({:board, 1}, fn -> :new end) == :new
  end

  test "an in-flight fill cannot cross a cache owner restart" do
    task = blocked_fill({:board, 1})
    old_pid = Process.whereis(FragmentCache)
    ref = Process.monitor(old_pid)
    GenServer.stop(old_pid, :normal)
    assert_receive {:DOWN, ^ref, :process, ^old_pid, :normal}
    assert is_pid(wait_for_restart(old_pid))
    send(task.pid, :finish_fill)
    assert Task.await(task) == :old
    assert FragmentCache.fetch_or_store({:board, 1}, fn -> :new end) == :new
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

  test "concurrent cache fills respect the configured entry limit" do
    Application.put_env(:eirinchan, :fragment_cache, max_entries: 4, ttl_ms: 60_000)

    1..40
    |> Task.async_stream(
      fn index -> FragmentCache.fetch_or_store({:parallel, index}, fn -> index end) end,
      max_concurrency: 40
    )
    |> Enum.each(fn {:ok, value} -> assert is_integer(value) end)

    assert FragmentCache.size() <= 4
  end

  defp blocked_fill(key) do
    parent = self()

    task =
      Task.async(fn ->
        FragmentCache.fetch_or_store(key, fn ->
          send(parent, {:fill_started, self()})
          receive do: (:finish_fill -> :old)
        end)
      end)

    assert_receive {:fill_started, pid} when pid == task.pid
    task
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
