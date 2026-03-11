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

  test "mark_seen does not create a watch for untracked threads" do
    assert {:ok, nil} = ThreadWatcher.mark_seen("token-1234567890123456", "bant", 999, 1000)
    refute ThreadWatcher.watched?("token-1234567890123456", "bant", 999)
  end

  test "unwatch_thread removes one watch" do
    assert {:ok, _watch} = ThreadWatcher.watch_thread("token-1234567890123456", "bant", 13)
    assert {:ok, 1} = ThreadWatcher.unwatch_thread("token-1234567890123456", "bant", 13)
    refute ThreadWatcher.watched?("token-1234567890123456", "bant", 13)
  end

  test "watch_state_for_board returns unread counts and watch_count totals" do
    board = board_fixture(%{uri: "watchstate", title: "Watch State"})
    thread = thread_fixture(board, %{body: "OP"})
    reply1 = reply_fixture(board, thread, %{body: "Reply one"})
    _reply2 = reply_fixture(board, thread, %{body: "Reply two"})

    assert {:ok, _watch} =
             ThreadWatcher.watch_thread("token-state-1234567890", board.uri, thread.id, %{
               last_seen_post_id: reply1.id
             })

    expected_last_seen = reply1.id
    state = ThreadWatcher.watch_state_for_board("token-state-1234567890", board.uri)

    assert %{watched: true, unread_count: 1, last_seen_post_id: ^expected_last_seen} =
             state[thread.id]

    assert ThreadWatcher.watch_count("token-state-1234567890") == 1
  end
end
