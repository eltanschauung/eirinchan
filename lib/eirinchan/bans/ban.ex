defmodule Eirinchan.Bans.Ban do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.Bans

  schema "bans" do
    field :ip_subnet, :string
    field :reason, :string
    field :expires_at, :utc_datetime_usec
    field :active, :boolean, default: true

    belongs_to :board, Eirinchan.Boards.BoardRecord
    belongs_to :mod_user, Eirinchan.Moderation.ModUser
    has_many :appeals, Eirinchan.Bans.Appeal

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ban, attrs) do
    ban
    |> cast(attrs, [:board_id, :mod_user_id, :ip_subnet, :reason, :expires_at, :active])
    |> validate_required([:ip_subnet])
    |> validate_change(:ip_subnet, fn :ip_subnet, value ->
      if Bans.valid_ip_mask?(value), do: [], else: [ip_subnet: "is invalid"]
    end)
    |> foreign_key_constraint(:board_id)
    |> foreign_key_constraint(:mod_user_id)
  end
end
