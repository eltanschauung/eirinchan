defmodule Eirinchan.Reports.Report do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reports" do
    field :reason, :string
    field :ip, :string
    field :dismissed_at, :utc_datetime_usec

    belongs_to :board, Eirinchan.Boards.BoardRecord
    belongs_to :post, Eirinchan.Posts.Post
    belongs_to :thread, Eirinchan.Posts.Post

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:board_id, :post_id, :thread_id, :reason, :ip, :dismissed_at])
    |> update_change(:reason, &normalize_reason/1)
    |> update_change(:ip, &normalize_ip/1)
    |> validate_required([:board_id, :post_id, :thread_id, :reason])
    |> foreign_key_constraint(:board_id)
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:thread_id)
    |> validate_length(:reason, min: 1, max: 2000)
  end

  def dismiss_changeset(report, attrs) do
    report
    |> cast(attrs, [:dismissed_at])
  end

  defp normalize_ip(nil), do: nil

  defp normalize_ip(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_reason(nil), do: nil

  defp normalize_reason(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
