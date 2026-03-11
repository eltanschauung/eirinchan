defmodule Eirinchan.ThreadWatcherTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.ThreadWatcher

  test "watch_thread upserts and watched_thread_ids batches" do
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 10)
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 11)
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 10)

    assert MapSet.new([10, 11]) ==
             ThreadWatcher.watched_thread_ids("token-1234567890123456", "bant")
  end

  test "mark_seen updates last_seen_post_id" do
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 12)
    assert {:ok, watch} = ThreadWatcher.mark_seen("token-1234567890123456", "bant", 12, 99)
    assert watch.last_seen_post_id == 99
  end

  test "unwatch_thread removes one watch" do
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 13)
    assert {:ok, 1} = ThreadWatcher.unwatch_thread("token-1234567890123456", "bant", 13)
    refute ThreadWatcher.watched?("token-1234567890123456", "bant", 13)
  end
end
