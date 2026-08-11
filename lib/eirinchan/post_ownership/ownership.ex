defmodule Eirinchan.PostOwnership.Ownership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.BrowserIdentity

  schema "post_ownerships" do
    field :browser_ref, :string, source: :browser_token
    belongs_to :post, Eirinchan.Posts.Post

    timestamps(updated_at: false)
  end

  def changeset(ownership, attrs) do
    ownership
    |> cast(attrs, [:browser_ref, :post_id])
    |> update_change(:browser_ref, &BrowserIdentity.reference/1)
    |> validate_required([:browser_ref, :post_id])
    |> validate_change(:browser_ref, fn :browser_ref, value ->
      if BrowserIdentity.reference?(value), do: [], else: [browser_ref: "is invalid"]
    end)
    |> unique_constraint([:browser_ref, :post_id],
      name: :post_ownerships_browser_token_post_id_index
    )
  end
end
