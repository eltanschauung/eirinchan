defmodule Eirinchan.Moderation.LogEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "moderation_logs" do
    field :actor_ip, :string
    field :board_uri, :string
    field :text, :string

    belongs_to :mod_user, Eirinchan.Moderation.ModUser

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:mod_user_id, :actor_ip, :board_uri, :text])
    |> update_change(:actor_ip, &normalize_string/1)
    |> update_change(:board_uri, &normalize_string/1)
    |> update_change(:text, &normalize_text/1)
    |> validate_required([:text])
    |> foreign_key_constraint(:mod_user_id)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(nil), do: nil

  defp normalize_text(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 4000)
    end
  end
end
