defmodule Eirinchan.BuildQueue do
  @moduledoc """
  Minimal queue for deferred board/thread rebuild jobs.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Locking
  alias Eirinchan.BuildQueue.Job
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Repo

  def enqueue_thread(%BoardRecord{} = board, thread_id, opts \\ []) do
    case driver(opts) do
      "fs" ->
        enqueue_pending(%{board_id: board.id, kind: "thread", thread_id: thread_id}, opts)

      "none" ->
        {:ok, %Job{board_id: board.id, kind: "thread", thread_id: thread_id, status: "pending"}}

      _ ->
        enqueue_pending(%{board_id: board.id, kind: "thread", thread_id: thread_id}, opts)
    end
  end

  def enqueue_indexes(%BoardRecord{} = board, opts \\ []) do
    case driver(opts) do
      "fs" ->
        enqueue_pending(%{board_id: board.id, kind: "indexes"}, opts)

      "none" ->
        {:ok, %Job{board_id: board.id, kind: "indexes", status: "pending"}}

      _ ->
        enqueue_pending(%{board_id: board.id, kind: "indexes"}, opts)
    end
  end

  def list_pending(opts \\ []) do
    case driver(opts) do
      "fs" ->
        list_pending_fs(opts)

      "none" ->
        []

      _ ->
        repo = Keyword.get(opts, :repo, Repo)
        board_id = Keyword.get(opts, :board_id)
        now = DateTime.utc_now()

        query =
          from job in Job,
            where:
              job.status == "pending" and
                (is_nil(job.available_at) or job.available_at <= ^now),
            order_by: [asc: job.inserted_at, asc: job.id]

        query =
          case board_id do
            nil -> query
            _ -> from job in query, where: job.board_id == ^board_id
          end

        repo.all(query)
    end
  end

  def mark_done(%Job{} = job, opts \\ []) do
    case driver(opts) do
      "fs" ->
        with {:ok, path} <- validated_fs_job_path(job, queue_config(opts)),
             :ok <- File.rm(path) do
          {:ok,
           %{
             job
             | status: "done",
               finished_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
           }}
        end

      "none" ->
        {:ok,
         %{
           job
           | status: "done",
             finished_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
         }}

      _ ->
        repo = Keyword.get(opts, :repo, Repo)
        job |> Job.done_changeset() |> repo.update()
    end
  end

  def mark_running(%Job{} = job, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    case driver(opts) do
      driver when driver in ["fs", "none"] -> {:ok, %{job | status: "running"}}
      _ -> job |> Job.running_changeset() |> repo.update()
    end
  end

  def mark_failed(%Job{} = job, reason, opts \\ []) do
    queue_config = queue_config(opts)

    max_attempts =
      opts
      |> Keyword.get(:max_attempts, Map.get(queue_config, :max_attempts, 3))
      |> normalize_max_attempts()

    repo = Keyword.get(opts, :repo, Repo)

    case driver(opts) do
      "fs" ->
        persist_fs_failure(job, reason, max_attempts, queue_config, opts)

      "none" ->
        {:ok, failed_job(job, reason, max_attempts)}

      _ ->
        job
        |> Job.failed_changeset(reason, max_attempts)
        |> repo.update()
    end
  end

  defp enqueue_pending(payload, opts) do
    if pending_exists?(payload, opts) do
      {:ok,
       %Job{
         board_id: payload.board_id,
         kind: payload.kind,
         thread_id: payload[:thread_id],
         status: "pending"
       }}
    else
      do_enqueue_pending(payload, opts)
    end
  end

  defp do_enqueue_pending(payload, opts) do
    case driver(opts) do
      "fs" ->
        enqueue_fs(payload, opts)

      _ ->
        repo = Keyword.get(opts, :repo, Repo)

        result =
          %Job{}
          |> Job.changeset(%{
            board_id: payload.board_id,
            kind: payload.kind,
            thread_id: payload[:thread_id]
          })
          |> repo.insert()

        case result do
          {:error, _changeset} = error -> find_active_job(payload, repo) || error
          success -> success
        end
    end
  end

  defp pending_exists?(payload, opts) do
    case driver(opts) do
      "fs" ->
        opts
        |> list_pending_fs()
        |> Enum.any?(&matches_payload?(&1, payload))

      "none" ->
        false

      _ ->
        repo = Keyword.get(opts, :repo, Repo)
        thread_id = Map.get(payload, :thread_id)

        query =
          from(
            job in Job,
            where:
              job.board_id == ^payload.board_id and
                job.kind == ^payload.kind and
                job.status in ["pending", "running"]
          )

        query =
          if is_nil(thread_id) do
            from(job in query, where: is_nil(job.thread_id))
          else
            from(job in query, where: job.thread_id == ^thread_id)
          end

        repo.exists?(query)
    end
  end

  defp find_active_job(payload, repo) do
    thread_id = Map.get(payload, :thread_id)

    query =
      from job in Job,
        where:
          job.board_id == ^payload.board_id and job.kind == ^payload.kind and
            job.status in ["pending", "running"]

    query =
      if is_nil(thread_id),
        do: from(job in query, where: is_nil(job.thread_id)),
        else: from(job in query, where: job.thread_id == ^thread_id)

    case repo.one(query) do
      nil -> nil
      job -> {:ok, job}
    end
  end

  defp matches_payload?(%Job{} = job, payload) do
    job.board_id == payload.board_id and
      job.kind == payload.kind and
      job.thread_id == Map.get(payload, :thread_id)
  end

  defp enqueue_fs(payload, opts) do
    queue_config = queue_config(opts)
    path = Path.join(queue_root(queue_config), queue_filename())
    directory = Path.dirname(path)
    _ = File.mkdir_p(directory)

    result =
      Locking.with_exclusive_lock(lock_config(opts), "build_queue", fn ->
        payload
        |> Map.put(:inserted_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
        |> Jason.encode!()
        |> then(&File.write(path, &1))
      end)

    case result do
      :ok ->
        {:ok,
         %Job{
           board_id: payload.board_id,
           kind: payload.kind,
           thread_id: payload[:thread_id],
           status: "pending",
           inserted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
           driver_meta: %{path: path, driver: "fs"}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_pending_fs(opts) do
    queue_config = queue_config(opts)
    board_id = Keyword.get(opts, :board_id)
    root = queue_root(queue_config)

    if File.dir?(root) do
      root
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(&fs_job_from_path/1)
      |> Enum.reject(&is_nil/1)
      |> maybe_filter_board(board_id)
    else
      []
    end
  end

  defp fs_job_from_path(path) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         board_id when is_integer(board_id) <- decoded["board_id"],
         kind when kind in ["thread", "indexes"] <- decoded["kind"],
         status when status in [nil, "pending"] <- decoded["status"] do
      inserted_at =
        case decoded["inserted_at"] do
          value when is_binary(value) ->
            case DateTime.from_iso8601(value) do
              {:ok, datetime, _offset} -> datetime
              _ -> DateTime.utc_now() |> DateTime.truncate(:microsecond)
            end

          _ ->
            DateTime.utc_now() |> DateTime.truncate(:microsecond)
        end

      %Job{
        board_id: board_id,
        kind: kind,
        thread_id: decoded["thread_id"],
        status: "pending",
        attempts: normalize_fs_attempts(decoded["attempts"]),
        last_error: normalize_fs_error(decoded["last_error"]),
        inserted_at: inserted_at,
        driver_meta: %{path: path, driver: "fs"}
      }
    else
      _ -> nil
    end
  end

  defp maybe_filter_board(jobs, nil), do: jobs
  defp maybe_filter_board(jobs, board_id), do: Enum.filter(jobs, &(&1.board_id == board_id))

  defp driver(opts) do
    opts
    |> queue_config()
    |> Map.get(:enabled, "db")
    |> case do
      true -> "fs"
      value when value in [nil, false, "none"] -> "none"
      value when is_binary(value) -> value
      _ -> "db"
    end
  end

  defp queue_config(opts) do
    opts
    |> Keyword.get(:config, %{})
    |> case do
      %{queue: queue} when is_map(queue) ->
        Map.merge(%{enabled: "db", path: "tmp/queue/build", max_attempts: 3}, queue)

      _ ->
        %{enabled: "db", path: "tmp/queue/build", max_attempts: 3}
    end
  end

  defp lock_config(opts) do
    opts
    |> Keyword.get(:config, %{})
    |> case do
      %{lock: lock} when is_map(lock) -> Map.merge(%{enabled: "none", path: "tmp/locks"}, lock)
      _ -> %{enabled: "none", path: "tmp/locks"}
    end
  end

  defp queue_root(queue_config) do
    queue_config
    |> Map.get(:path, "tmp/queue/build")
    |> Path.expand(project_root())
  end

  defp queue_filename do
    timestamp =
      System.system_time(:microsecond)
      |> Integer.to_string()
      |> String.pad_leading(20, "0")

    "#{timestamp}-#{System.unique_integer([:positive])}.json"
  end

  defp persist_fs_failure(job, reason, max_attempts, queue_config, opts) do
    Locking.with_exclusive_lock(lock_config(opts), "build_queue", fn ->
      with {:ok, path} <- validated_fs_job_path(job, queue_config),
           {:ok, body} <- File.read(path),
           {:ok, payload} when is_map(payload) <- Jason.decode(body) do
        persisted_attempts = normalize_fs_attempts(payload["attempts"])
        attempts = max(persisted_attempts, normalize_fs_attempts(job.attempts)) + 1
        terminal? = attempts >= max_attempts
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
        error = format_failure(reason)

        updated_payload =
          payload
          |> Map.put("status", if(terminal?, do: "failed", else: "pending"))
          |> Map.put("attempts", attempts)
          |> Map.put("last_error", error)
          |> Map.put("started_at", nil)
          |> Map.put("available_at", nil)
          |> maybe_put_finished_at(terminal?, now)

        with :ok <- atomic_write_json(path, updated_payload),
             :ok <- maybe_archive_fs_failure(path, terminal?, queue_config) do
          {:ok,
           %{
             job
             | status: if(terminal?, do: "failed", else: "pending"),
               attempts: attempts,
               last_error: error,
               started_at: nil,
               available_at: nil,
               finished_at: if(terminal?, do: now, else: nil)
           }}
        end
      else
        {:error, _reason} = error -> error
        _other -> {:error, :invalid_queue_job}
      end
    end)
  end

  defp failed_job(job, reason, max_attempts) do
    attempts = normalize_fs_attempts(job.attempts) + 1
    terminal? = attempts >= max_attempts

    %{
      job
      | status: if(terminal?, do: "failed", else: "pending"),
        attempts: attempts,
        last_error: format_failure(reason),
        started_at: nil,
        available_at: nil,
        finished_at:
          if(terminal?, do: DateTime.utc_now() |> DateTime.truncate(:microsecond), else: nil)
    }
  end

  defp maybe_put_finished_at(payload, true, now),
    do: Map.put(payload, "finished_at", DateTime.to_iso8601(now))

  defp maybe_put_finished_at(payload, false, _now), do: Map.put(payload, "finished_at", nil)

  defp maybe_archive_fs_failure(_path, false, _queue_config), do: :ok

  defp maybe_archive_fs_failure(path, true, queue_config) do
    failed_root = Path.join(queue_root(queue_config), "failed")

    with :ok <- File.mkdir_p(failed_root) do
      File.rename(path, Path.join(failed_root, Path.basename(path)))
    end
  end

  defp validated_fs_job_path(job, queue_config) do
    with path when is_binary(path) <- get_in(job.driver_meta || %{}, [:path]),
         expanded <- Path.expand(path),
         root <- queue_root(queue_config),
         true <- Path.dirname(expanded) == root,
         ".json" <- Path.extname(expanded),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(expanded) do
      {:ok, expanded}
    else
      _other -> {:error, :invalid_job_path}
    end
  end

  defp atomic_write_json(path, payload) do
    temporary_path = path <> ".tmp-#{System.unique_integer([:positive])}"

    with {:ok, encoded} <- Jason.encode(payload),
         :ok <- File.write(temporary_path, encoded, [:binary, :exclusive]),
         :ok <- File.rename(temporary_path, path) do
      :ok
    else
      {:error, _reason} = error ->
        _ = File.rm(temporary_path)
        error
    end
  end

  defp normalize_max_attempts(value) when is_integer(value) and value > 0, do: min(value, 100)
  defp normalize_max_attempts(_value), do: 3

  defp normalize_fs_attempts(value) when is_integer(value) and value >= 0, do: value
  defp normalize_fs_attempts(_value), do: 0

  defp normalize_fs_error(value) when is_binary(value), do: String.slice(value, 0, 2_000)
  defp normalize_fs_error(_value), do: nil

  defp format_failure(reason),
    do: reason |> inspect(limit: 20, printable_limit: 1_500) |> String.slice(0, 2_000)

  defp project_root do
    case Application.get_env(:eirinchan, :instance_config_path) do
      path when is_binary(path) -> Path.expand("..", Path.dirname(path))
      _ -> File.cwd!()
    end
  end
end
