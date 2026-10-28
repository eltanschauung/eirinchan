defmodule Eirinchan.ThreadCacheConfigTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.Posts
  alias Eirinchan.Runtime.Config
  alias EirinchanWeb.FragmentCache

  setup do
    FragmentCache.clear()
    on_exit(&FragmentCache.clear/0)
    :ok
  end

  test "thread views do not reuse values across different noko50 settings" do
    board = board_fixture()
    thread = thread_fixture(board)
    reply_fixture(board, thread, %{body: "One"})
    reply_fixture(board, thread, %{body: "Two"})

    low = Config.compose(nil, %{}, %{noko50_min: 1, noko50_count: 1})
    high = Config.compose(nil, %{}, %{noko50_min: 10, noko50_count: 7})

    assert {:ok, first} = Posts.get_thread_view(board, thread.id, config: low)
    assert first.has_noko50 and first.last_count == 1
    assert {:ok, second} = Posts.get_thread_view(board, thread.id, config: high)
    refute second.has_noko50
    assert second.last_count == 7

    assert {:ok, truncated} = Posts.get_thread_view(board, thread.id, config: low, last_posts: 1)
    assert length(truncated.replies) == 1

    assert {:ok, untruncated} =
             Posts.get_thread_view(board, thread.id, config: high, last_posts: 1)

    assert length(untruncated.replies) == 2
  end

  test "board summaries do not reuse values across different noko50 settings" do
    board = board_fixture()
    thread = thread_fixture(board)
    reply_fixture(board, thread, %{body: "One"})
    reply_fixture(board, thread, %{body: "Two"})

    low = Config.compose(nil, %{}, %{noko50_min: 1, noko50_count: 1})
    high = Config.compose(nil, %{}, %{noko50_min: 10, noko50_count: 7})

    assert {:ok, %{threads: [first]}} = Posts.list_threads_page(board, 1, config: low)
    assert first.has_noko50 and first.last_count == 1
    assert {:ok, %{threads: [second]}} = Posts.list_threads_page(board, 1, config: high)
    refute second.has_noko50
    assert second.last_count == 7
  end
end
