defmodule Eirinchan.Antispam.SearchQuery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "search_queries" do
    field :ip_subnet, :string
    field :browser_ref, :string
    field :client_key, :string
    field :query, :string

    belongs_to :board, Eirinchan.Boards.BoardRecord

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:board_id, :ip_subnet, :browser_ref, :client_key, :query])
    |> validate_required([:ip_subnet, :query])
    |> foreign_key_constraint(:board_id)
  end
end
