defmodule Eirinchan.BuildQueueDriverTest do
  use Eirinchan.DataCase, async: false

  import Ecto.Query

  alias Eirinchan.BuildQueue
  alias Eirinchan.Repo
  alias Eirinchan.BuildQueue.Job

  test "filesystem queue driver enqueues, lists, and marks jobs done" do
    board = board_fixture()

    root = Path.join(System.tmp_dir!(), "eirinchan-queue-#{System.unique_integer([:positive])}")

    config = %{
      queue: %{enabled: "fs", path: root},
      lock: %{enabled: "fs", path: root <> "-locks"}
    }

    _ = File.rm_rf(root)
    _ = File.rm_rf(root <> "-locks")

    assert {:ok, _thread_job} = BuildQueue.enqueue_thread(board, 123, config: config)
    assert {:ok, _index_job} = BuildQueue.enqueue_indexes(board, config: config)

    jobs = BuildQueue.list_pending(config: config, board_id: board.id)
    assert Enum.map(jobs, & &1.kind) == ["thread", "indexes"]

    assert {:ok, _done} = BuildQueue.mark_done(hd(jobs), config: config)

    assert Enum.map(BuildQueue.list_pending(config: config, board_id: board.id), & &1.kind) == [
             "indexes"
           ]
  end

  test "none queue driver drops jobs" do
    board = board_fixture()
    config = %{queue: %{enabled: "none"}, lock: %{enabled: "none"}}

    assert {:ok, _job} = BuildQueue.enqueue_thread(board, 1, config: config)
    assert BuildQueue.list_pending(config: config, board_id: board.id) == []
  end

  test "db queue driver deduplicates pending jobs" do
    board = board_fixture()

    assert {:ok, _job} = BuildQueue.enqueue_thread(board, 123)
    assert {:ok, _job} = BuildQueue.enqueue_thread(board, 123)
    assert {:ok, _job} = BuildQueue.enqueue_indexes(board)
    assert {:ok, _job} = BuildQueue.enqueue_indexes(board)

    pending =
      Repo.all(from job in Job, where: job.board_id == ^board.id and job.status == "pending")

    assert Enum.count(pending, &(&1.kind == "thread" and &1.thread_id == 123)) == 1
    assert Enum.count(pending, &(&1.kind == "indexes")) == 1
  end
end
