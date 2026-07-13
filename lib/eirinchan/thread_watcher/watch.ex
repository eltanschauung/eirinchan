defmodule Eirinchan.ThreadWatcher.Watch do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.BrowserIdentity

  schema "thread_watches" do
    field :browser_token, :string
    field :board_uri, :string
    field :thread_id, :integer
    field :last_seen_post_id, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(watch, attrs) do
    watch
    |> cast(attrs, [:browser_token, :board_uri, :thread_id, :last_seen_post_id])
    |> update_change(:browser_token, &BrowserIdentity.reference/1)
    |> validate_required([:browser_token, :board_uri, :thread_id])
    |> validate_change(:browser_token, fn :browser_token, value ->
      if BrowserIdentity.reference?(value), do: [], else: [browser_token: "is invalid"]
    end)
    |> validate_length(:board_uri, min: 1, max: 32)
    |> validate_number(:thread_id, greater_than: 0)
    |> unique_constraint([:browser_token, :board_uri, :thread_id],
      name: :thread_watches_browser_token_board_uri_thread_id_index
    )
  end
end
