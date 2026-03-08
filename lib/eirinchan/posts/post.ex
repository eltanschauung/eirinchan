defmodule Eirinchan.Posts.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :name, :string
    field :email, :string
    field :subject, :string
    field :password, :string
    field :body, :string
    field :embed, :string
    field :flag_codes, {:array, :string}, default: []
    field :flag_alts, {:array, :string}, default: []
    field :tag, :string
    field :proxy, :string
    field :ip_subnet, :string
    field :tripcode, :string
    field :file_name, :string
    field :file_path, :string
    field :thumb_path, :string
    field :file_size, :integer
    field :file_type, :string
    field :file_md5, :string
    field :image_width, :integer
    field :image_height, :integer
    field :spoiler, :boolean, default: false
    field :bump_at, :utc_datetime_usec
    field :sticky, :boolean, default: false
    field :locked, :boolean, default: false
    field :cycle, :boolean, default: false
    field :sage, :boolean, default: false
    field :slug, :string

    belongs_to :board, Eirinchan.Boards.BoardRecord
    belongs_to :thread, __MODULE__
    has_many :extra_files, Eirinchan.Posts.PostFile

    timestamps(type: :utc_datetime)
  end

  def create_changeset(post, attrs) do
    post
    |> cast(attrs, [
      :board_id,
      :thread_id,
      :name,
      :email,
      :subject,
      :password,
      :body,
      :embed,
      :flag_codes,
      :flag_alts,
      :tag,
      :proxy,
      :ip_subnet,
      :tripcode,
      :file_name,
      :file_path,
      :thumb_path,
      :file_size,
      :file_type,
      :file_md5,
      :image_width,
      :image_height,
      :spoiler,
      :bump_at,
      :sticky,
      :locked,
      :cycle,
      :sage,
      :slug
    ])
    |> update_change(:name, &normalize_string/1)
    |> update_change(:email, &normalize_string/1)
    |> update_change(:subject, &normalize_string/1)
    |> update_change(:password, &normalize_string/1)
    |> update_change(:body, &normalize_body/1)
    |> update_change(:embed, &normalize_string/1)
    |> ensure_body()
    |> validate_required([:board_id])
    |> foreign_key_constraint(:board_id)
    |> foreign_key_constraint(:thread_id)
  end

  def thread_state_changeset(post, attrs) do
    post
    |> cast(attrs, [:sticky, :locked, :cycle, :sage])
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_body(nil), do: ""

  defp normalize_body(value) do
    value
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.trim()
  end

  defp ensure_body(changeset) do
    if get_field(changeset, :body) == nil do
      put_change(changeset, :body, "")
    else
      changeset
    end
  end
end
