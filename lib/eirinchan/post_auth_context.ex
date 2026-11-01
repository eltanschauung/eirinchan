defmodule Eirinchan.PostAuthContext do
  @moduledoc "Private authentication evidence; never part of public post serialization."
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:post_id, :id, autogenerate: false}
  @derive {Inspect, except: [:auth_password]}
  schema "post_auth_contexts" do
    field :auth_password, :string
    field :authenticated_at, :utc_datetime_usec
    field :auth_age_seconds, :integer
    field :country_code, :string
  end

  def changeset(context, attrs) do
    context
    |> cast(attrs, [:post_id, :auth_password, :authenticated_at, :auth_age_seconds, :country_code])
    |> validate_required([:post_id])
    |> foreign_key_constraint(:post_id)
  end
end
