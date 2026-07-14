defmodule Eirinchan.CustomPages.Page do
  use Ecto.Schema
  import Ecto.Changeset

  schema "custom_pages" do
    field :slug, :string
    field :title, :string
    field :body, :string

    belongs_to :mod_user, Eirinchan.Moderation.ModUser

    timestamps(type: :utc_datetime)
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:slug, :title, :body, :mod_user_id])
    |> update_change(:slug, &normalize_slug/1)
    |> update_change(:title, &normalize/1)
    |> update_change(:body, &normalize/1)
    |> validate_required([:slug, :title, :body, :mod_user_id])
    |> validate_format(:slug, ~r/^[a-z0-9_-]+$/)
    |> validate_exclusion(:slug, ["home"], message: "is reserved for the RecentPosts theme")
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:mod_user_id)
  end

  defp normalize(nil), do: nil

  defp normalize(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_slug(nil), do: nil

  defp normalize_slug(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> nil
      slug -> slug
    end
  end
end
