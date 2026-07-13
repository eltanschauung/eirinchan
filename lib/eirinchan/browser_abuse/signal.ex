defmodule Eirinchan.BrowserAbuse.Signal do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.BrowserIdentity

  @primary_key {:browser_ref, :string, autogenerate: false}
  @derive {Inspect, except: [:browser_ref, :client_key]}

  schema "browser_abuse_signals" do
    field :client_key, :string
    field :reason, :string
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [:browser_ref, :client_key, :reason, :expires_at])
    |> validate_required([:browser_ref, :reason, :expires_at])
    |> validate_length(:reason, max: 64)
    |> validate_change(:browser_ref, fn :browser_ref, value ->
      if BrowserIdentity.reference?(value), do: [], else: [browser_ref: "is invalid"]
    end)
  end
end
