defmodule Eirinchan.PostOwnership.Ownership do
  use Ecto.Schema
  import Ecto.Changeset

  schema "post_ownerships" do
    field :browser_token, :string
    belongs_to :post, Eirinchan.Posts.Post

    timestamps(updated_at: false)
  end

  def changeset(ownership, attrs) do
    ownership
    |> cast(attrs, [:browser_token, :post_id])
    |> validate_required([:browser_token, :post_id])
    |> validate_length(:browser_token, min: 16, max: 128)
    |> unique_constraint([:browser_token, :post_id],
      name: :post_ownerships_browser_token_post_id_index
    )
  end
end
