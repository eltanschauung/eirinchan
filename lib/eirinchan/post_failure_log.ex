defmodule Eirinchan.PostFailureLog do
  use Ecto.Schema
  import Ecto.Changeset

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
end
