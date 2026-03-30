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

        query =
          from job in Job,
            where: job.status == "pending",
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
        path = get_in(job.driver_meta || %{}, [:path])
        if path, do: File.rm(path)

        {:ok,
         %{
           job
           | status: "done",
             finished_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
         }}

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

        %Job{}
        |> Job.changeset(%{
          board_id: payload.board_id,
          kind: payload.kind,
          thread_id: payload[:thread_id]
        })
        |> repo.insert()
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
                job.status == "pending"
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
         kind when kind in ["thread", "indexes"] <- decoded["kind"] do
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
        Map.merge(%{enabled: "db", path: "tmp/queue/build"}, queue)

      _ ->
        %{enabled: "db", path: "tmp/queue/build"}
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

  defp project_root do
    case Application.get_env(:eirinchan, :instance_config_path) do
      path when is_binary(path) -> Path.expand("..", Path.dirname(path))
      _ -> File.cwd!()
    end
  end
end
