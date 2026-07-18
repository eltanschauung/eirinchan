defmodule Eirinchan.Feedback.Entry do
  use Ecto.Schema
  import Ecto.Changeset
  alias Eirinchan.Runtime.Config

  schema "feedback" do
    field :name, :string
    field :email, :string
    field :body, :string
    field :ip_subnet, :string
    field :read_at, :utc_datetime_usec

    has_many :comments, Eirinchan.Feedback.Comment, foreign_key: :feedback_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs), do: changeset(entry, attrs, Config.default_config())

  def changeset(entry, attrs, config) do
    entry
    |> cast(attrs, [:name, :email, :body, :ip_subnet, :read_at])
    |> update_change(:name, &normalize_string/1)
    |> update_change(:email, &normalize_string/1)
    |> update_change(:body, &normalize_string/1)
    |> validate_required([:body, :ip_subnet])
    |> validate_length(:name, max: bounded_limit(config, :feedback_name_max_length, 255, 255))
    |> validate_length(:email, max: bounded_limit(config, :feedback_email_max_length, 255, 255))
    |> validate_length(:body,
      min: 1,
      max: positive_limit(config, :feedback_body_max_length, 4_000)
    )
  end

  def mark_read_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:read_at])
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

  defp positive_limit(config, key, default) do
    case Map.get(config, key) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end

  defp bounded_limit(config, key, default, maximum),
    do: min(positive_limit(config, key, default), maximum)
end
