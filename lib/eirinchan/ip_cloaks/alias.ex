defmodule Eirinchan.IpCloaks.Alias do
  use Ecto.Schema
  import Ecto.Changeset

  @token_pattern ~r/\Ac2_[A-Za-z0-9_-]{13}\z/

  schema "ip_cloak_aliases" do
    field :token, :string
    field :payload, :string
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(alias_record, attrs) do
    alias_record
    |> cast(attrs, [:token, :payload, :expires_at])
    |> validate_required([:token, :payload, :expires_at])
    |> validate_format(:token, @token_pattern)
    |> validate_length(:token, is: 16)
    |> validate_length(:payload, max: 128)
    |> unique_constraint(:token)
  end
end
