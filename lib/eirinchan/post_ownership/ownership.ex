defmodule Eirinchan.PostOwnership.Ownership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.BrowserIdentity

  schema "post_ownerships" do
    field :browser_token, :string
    belongs_to :post, Eirinchan.Posts.Post

    timestamps(updated_at: false)
  end

  def changeset(ownership, attrs) do
    ownership
    |> cast(attrs, [:browser_token, :post_id])
    |> update_change(:browser_token, &BrowserIdentity.reference/1)
    |> validate_required([:browser_token, :post_id])
    |> validate_change(:browser_token, fn :browser_token, value ->
      if BrowserIdentity.reference?(value), do: [], else: [browser_token: "is invalid"]
    end)
    |> unique_constraint([:browser_token, :post_id],
      name: :post_ownerships_browser_token_post_id_index
    )
  end
end
