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

  test "filesystem queue persists attempts and archives terminal failures" do
    board = board_fixture()
    root = Path.join(System.tmp_dir!(), "eirinchan-queue-retries-#{System.unique_integer([:positive])}")
    config = %{queue: %{enabled: "fs", path: root, max_attempts: 2}, lock: %{enabled: "fs", path: root <> "-locks"}}

    on_exit(fn ->
      _ = File.rm_rf(root)
      _ = File.rm_rf(root <> "-locks")
    end)

    assert {:ok, _job} = BuildQueue.enqueue_thread(board, 123, config: config)
    [job] = BuildQueue.list_pending(config: config)
    assert {:ok, retrying} = BuildQueue.mark_failed(job, :decoder_failed, config: config)
    assert retrying.attempts == 1

    [persisted] = BuildQueue.list_pending(config: config)
    assert persisted.attempts == 1
    assert persisted.last_error =~ "decoder_failed"
    assert {:ok, failed} = BuildQueue.mark_failed(persisted, :decoder_failed, config: config)
    assert failed.status == "failed"
    assert BuildQueue.list_pending(config: config) == []
    assert length(Path.wildcard(Path.join([root, "failed", "*.json"]))) == 1
  end

  test "filesystem queue rejects driver metadata outside its configured root" do
    root = Path.join(System.tmp_dir!(), "eirinchan-queue-root-#{System.unique_integer([:positive])}")
    outside = Path.join(System.tmp_dir!(), "eirinchan-queue-outside-#{System.unique_integer([:positive])}.json")
    config = %{queue: %{enabled: "fs", path: root}, lock: %{enabled: "none"}}
    File.write!(outside, "do not remove")

    on_exit(fn ->
      _ = File.rm_rf(root)
      _ = File.rm(outside)
    end)

    forged = %Job{status: "pending", driver_meta: %{path: outside}}

    assert {:error, :invalid_job_path} = BuildQueue.mark_done(forged, config: config)
    assert {:error, :invalid_job_path} = BuildQueue.mark_failed(forged, :failed, config: config)
    assert File.read!(outside) == "do not remove"

    File.mkdir_p!(root)
    symlink = Path.join(root, "forged.json")
    assert :ok = File.ln_s(outside, symlink)
    forged_symlink = %Job{status: "pending", driver_meta: %{path: symlink}}

    assert {:error, :invalid_job_path} =
             BuildQueue.mark_failed(forged_symlink, :failed, config: config)

    assert File.read!(outside) == "do not remove"
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

  test "db queue records failures and stops retrying at the attempt limit" do
    board = board_fixture()
    assert {:ok, job} = BuildQueue.enqueue_thread(board, 123)
    assert {:ok, running} = BuildQueue.mark_running(job)

    assert {:ok, retrying} = BuildQueue.mark_failed(running, :decoder_failed, max_attempts: 2)
    assert retrying.status == "pending"
    assert retrying.attempts == 1
    assert retrying.last_error =~ "decoder_failed"

    assert {:ok, running_again} = BuildQueue.mark_running(retrying)
    assert {:ok, failed} = BuildQueue.mark_failed(running_again, :decoder_failed, max_attempts: 2)
    assert failed.status == "failed"
    assert failed.attempts == 2
    assert failed.finished_at
    assert BuildQueue.list_pending(board_id: board.id) == []
  end
end
