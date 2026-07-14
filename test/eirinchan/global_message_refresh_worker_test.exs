defmodule Eirinchan.GlobalMessageRefreshWorkerTest do
  use ExUnit.Case, async: false

  alias Eirinchan.GlobalMessageRefreshWorker
  alias EirinchanWeb.FragmentCache

  setup do
    FragmentCache.clear()
    on_exit(&FragmentCache.clear/0)
    :ok
  end

  test "uses the configured refresh interval and defaults invalid values to 30 seconds" do
    assert GlobalMessageRefreshWorker.interval_seconds(%{}) == 30
    assert GlobalMessageRefreshWorker.interval_seconds(%{global_message_refresh_seconds: 7}) == 7
    assert GlobalMessageRefreshWorker.interval_seconds(%{global_message_refresh_seconds: 0}) == 30

    assert GlobalMessageRefreshWorker.interval_seconds(%{global_message_refresh_seconds: "7"}) ==
             30
  end

  test "periodically refreshes and reads the current config again" do
    test_pid = self()
    {:ok, config} = Agent.start_link(fn -> %{global_message_refresh_seconds: 1} end)

    worker =
      start_supervised!(
        {GlobalMessageRefreshWorker,
         name: nil,
         config_provider: fn ->
           send(test_pid, :config_read)
           Agent.get(config, & &1)
         end,
         refresh: fn -> send(test_pid, :refreshed) end,
         initial_delay_ms: 1}
      )

    assert_receive :refreshed, 500
    assert_receive :config_read, 500
    assert Process.alive?(worker)
  end

  test "refreshes announcement and document hashes without flushing unrelated fragments" do
    refreshed = [
      {:announcement_global_message, :message},
      {:tf2_player_count, 1},
      {:board_fragment_md5, :board},
      {:thread_fragment_md5, :thread}
    ]

    Enum.each(refreshed, fn key ->
      assert FragmentCache.fetch_or_store(key, fn -> :old end) == :old
    end)

    assert FragmentCache.fetch_or_store({:post_view, 1}, fn -> :kept end) == :kept

    worker =
      start_supervised!(
        {GlobalMessageRefreshWorker,
         name: nil, config_provider: fn -> %{} end, initial_delay_ms: 60_000}
      )

    assert :ok = GlobalMessageRefreshWorker.refresh_now(worker)

    Enum.each(refreshed, fn key ->
      assert FragmentCache.fetch_or_store(key, fn -> :new end) == :new
    end)

    assert FragmentCache.fetch_or_store({:post_view, 1}, fn -> :changed end) == :kept
  end
end
