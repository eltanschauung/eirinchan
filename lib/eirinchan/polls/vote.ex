defmodule Eirinchan.Polls.Vote do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "poll_votes" do
    belongs_to :post, Eirinchan.Posts.Post
    field :choice, :integer
    field :ip_ref, :string
    field :browser_ref, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:post_id, :choice, :ip_ref, :browser_ref])
    |> validate_required([:post_id, :choice, :ip_ref])
    |> validate_number(:choice, greater_than_or_equal_to: 0, less_than: 6)
    |> foreign_key_constraint(:post_id)
    |> unique_constraint([:post_id, :ip_ref])
    |> unique_constraint([:post_id, :browser_ref])
    |> check_constraint(:choice, name: :poll_votes_choice)
  end
end
