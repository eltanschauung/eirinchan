defmodule Eirinchan.Noticeboard.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "noticeboard_entries" do
    field :subject, :string
    field :body_html, :string
    field :author_name, :string
    field :posted_at, :naive_datetime_usec

    belongs_to :mod_user, Eirinchan.Moderation.ModUser

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:subject, :body_html, :author_name, :posted_at, :mod_user_id])
    |> update_change(:subject, &normalize_string/1)
    |> update_change(:body_html, &normalize_string/1)
    |> update_change(:author_name, &normalize_string/1)
    |> validate_required([:body_html, :author_name, :posted_at])
    |> validate_length(:subject, max: 255)
    |> validate_length(:author_name, min: 1, max: 64)
    |> foreign_key_constraint(:mod_user_id)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) do
    case value |> to_string() |> String.trim() do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
