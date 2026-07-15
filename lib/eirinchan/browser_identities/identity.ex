defmodule Eirinchan.BrowserIdentities.Identity do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.BrowserIdentity

  @primary_key {:browser_ref, :string, autogenerate: false}
  @derive {Inspect, except: [:browser_ref]}

  schema "browser_identities" do
    field :issued_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :presence_seen_at, :utc_datetime
    field :expires_at, :utc_datetime
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:browser_ref, :issued_at, :last_seen_at, :presence_seen_at, :expires_at])
    |> validate_required([:browser_ref, :issued_at, :last_seen_at, :expires_at])
    |> validate_change(:browser_ref, fn :browser_ref, value ->
      if BrowserIdentity.reference?(value), do: [], else: [browser_ref: "is invalid"]
    end)
  end
end
