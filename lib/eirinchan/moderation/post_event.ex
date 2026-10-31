defmodule Eirinchan.Moderation.PostEvent do
  @moduledoc """
  Private, durable metadata for B24 bans and attachment deletions.

  No post body, media bytes, credentials, or public serialization is retained.
  File metadata is captured before deletion; previously deleted files are excluded.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "moderation_post_events" do
    field :action, :string
    field :post_id, :integer
    field :public_post_id, :integer
    field :board_uri, :string
    field :ip_subnet, :string
    field :banned_subnet, :string
    field :file_count, :integer

    embeds_many :files, FileSnapshot, primary_key: false do
      field :position, :integer
      field :file_name, :string
      field :file_md5, :string
      field :file_size, :integer
    end

    belongs_to :mod_user, Eirinchan.Moderation.ModUser
    belongs_to :ban, Eirinchan.Bans.Ban
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :action,
      :post_id,
      :public_post_id,
      :board_uri,
      :ip_subnet,
      :banned_subnet,
      :file_count,
      :mod_user_id,
      :ban_id
    ])
    |> cast_embed(:files, with: &file_changeset/2)
    |> validate_required([
      :action,
      :post_id,
      :public_post_id,
      :board_uri,
      :ip_subnet,
      :banned_subnet,
      :file_count
    ])
    |> validate_inclusion(:action, ["ban24"])
    |> validate_number(:file_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:mod_user_id)
    |> foreign_key_constraint(:ban_id)
    |> check_constraint(:file_count, name: :moderation_post_events_file_count)
  end

  defp file_changeset(file, attrs) do
    # Legacy metadata may be incomplete. Preserve that absence instead of
    # inventing a hash/size or blocking moderation of an old attachment.
    cast(file, attrs, [:position, :file_name, :file_md5, :file_size], empty_values: [])
  end
end
