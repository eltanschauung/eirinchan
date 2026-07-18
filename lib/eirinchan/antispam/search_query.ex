defmodule Eirinchan.Antispam.SearchQuery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "search_queries" do
    field :ip_subnet, :string
    field :browser_ref, :string
    field :client_key, :string
    field :activity, :string

    belongs_to :board, Eirinchan.Boards.BoardRecord

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:board_id, :ip_subnet, :browser_ref, :client_key, :activity])
    |> validate_required([:ip_subnet, :activity])
    |> validate_format(:activity, ~r/^[a-z][a-z0-9_-]{0,31}$/)
    |> foreign_key_constraint(:board_id)
  end
end
