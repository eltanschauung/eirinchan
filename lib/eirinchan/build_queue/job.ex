defmodule Eirinchan.BuildQueue.Job do
  use Ecto.Schema
  import Ecto.Changeset

  schema "build_jobs" do
    field :kind, :string
    field :thread_id, :integer
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :last_error, :string
    field :started_at, :utc_datetime_usec
    field :available_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :driver_meta, :map, virtual: true

    belongs_to :board, Eirinchan.Boards.BoardRecord

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :board_id,
      :kind,
      :thread_id,
      :status,
      :attempts,
      :last_error,
      :started_at,
      :available_at,
      :finished_at
    ])
    |> validate_required([:board_id, :kind])
    |> validate_inclusion(:kind, ["thread", "indexes"])
    |> validate_inclusion(:status, ["pending", "running", "done", "failed"])
    |> foreign_key_constraint(:board_id)
    |> unique_constraint(:board_id, name: :build_jobs_active_unique_index)
  end

  def running_changeset(job) do
    change(job,
      status: "running",
      started_at: now(),
      available_at: nil,
      last_error: nil
    )
  end

  def done_changeset(job) do
    change(job, status: "done", finished_at: now(), last_error: nil)
  end

  def failed_changeset(job, reason, max_attempts \\ 3) do
    attempts = (job.attempts || 0) + 1
    terminal? = attempts >= max_attempts

    change(job,
      status: if(terminal?, do: "failed", else: "pending"),
      attempts: attempts,
      last_error: reason |> inspect(limit: 20, printable_limit: 1_500) |> String.slice(0, 2_000),
      started_at: nil,
      available_at: nil,
      finished_at: if(terminal?, do: now(), else: nil)
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
