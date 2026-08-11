defmodule Eirinchan.ThreadWatcher.Watch do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.BrowserIdentity

  schema "thread_watches" do
    field :browser_ref, :string, source: :browser_token
    field :board_uri, :string
    field :thread_id, :integer
    field :last_seen_post_id, :integer
    field :activated, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(watch, attrs) do
    watch
    |> cast(attrs, [:browser_ref, :board_uri, :thread_id, :last_seen_post_id, :activated])
    |> update_change(:browser_ref, &BrowserIdentity.reference/1)
    |> validate_required([:browser_ref, :board_uri, :thread_id])
    |> validate_change(:browser_ref, fn :browser_ref, value ->
      if BrowserIdentity.reference?(value), do: [], else: [browser_ref: "is invalid"]
    end)
    |> validate_length(:board_uri, min: 1, max: 32)
    |> validate_number(:thread_id, greater_than: 0)
    |> validate_inclusion(:activated, [true, false])
    |> unique_constraint([:browser_ref, :thread_id],
      name: :thread_watches_browser_token_thread_id_index
    )
    |> foreign_key_constraint(:thread_id)
  end
end
