defmodule Eirinchan.PostFailureLog do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "post_failure_logs" do
    field :event, :string
    field :level, :string
    field :board_uri, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:event, :level, :board_uri, :metadata])
    |> validate_required([:event, :level, :metadata])
  end

  def purge_old(config, opts \\ []) do
    repo = Keyword.get(opts, :repo, Eirinchan.Repo)
    retention_days = max(Map.get(config, :post_failure_log_retention_days, 7), 1)
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400, :second)

    {count, _rows} =
      repo.delete_all(from log in __MODULE__, where: log.inserted_at < ^cutoff)

    count
  end
end
