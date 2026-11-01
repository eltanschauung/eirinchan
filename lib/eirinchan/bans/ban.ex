defmodule Eirinchan.Bans.Ban do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.Bans
  alias Eirinchan.Bans.TargetResolver

  schema "bans" do
    field :ip_subnet, :string
    field :user_agent, :string
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
    |> cast(attrs, [
      :board_id,
      :mod_user_id,
      :ip_subnet,
      :user_agent,
      :reason,
      :expires_at,
      :active
    ])
    |> update_change(:ip_subnet, &TargetResolver.normalize_for_storage/1)
    |> update_change(:user_agent, &trim_agent/1)
    |> validate_length(:user_agent, max: 1024, count: :bytes)
    |> validate_change(:user_agent, fn :user_agent, value ->
      if Eirinchan.ClientMetadata.user_agent(value), do: [], else: [user_agent: "is invalid"]
    end)
    |> validate_target()
    |> validate_change(:ip_subnet, fn :ip_subnet, value ->
      if Bans.valid_ip_mask?(value), do: [], else: [ip_subnet: "is invalid"]
    end)
    |> foreign_key_constraint(:board_id)
    |> foreign_key_constraint(:mod_user_id)
    |> check_constraint(:ip_subnet, name: :bans_target)
  end

  defp validate_target(changeset) do
    if get_field(changeset, :ip_subnet) in [nil, ""] and
         get_field(changeset, :user_agent) in [nil, ""],
       do: add_error(changeset, :ip_subnet, "IP or User-Agent is required"),
       else: changeset
  end

  defp trim_agent(nil), do: nil
  defp trim_agent(value), do: String.trim(value)
end
