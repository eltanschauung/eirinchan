defmodule Eirinchan.Antispam.FloodEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "flood_entries" do
    field :ip_subnet, :string
    field :browser_ref, :string
    field :client_key, :string
    field :body_hash, :string

    belongs_to :board, Eirinchan.Boards.BoardRecord

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:board_id, :ip_subnet, :browser_ref, :client_key, :body_hash])
    |> validate_required([:board_id, :ip_subnet])
    |> foreign_key_constraint(:board_id)
  end
end
