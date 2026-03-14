defmodule Eirinchan.Boards.BoardRecord do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eirinchan.Boards.Board
  alias Eirinchan.Runtime.Config

  schema "boards" do
    field :uri, :string
    field :title, :string
    field :subtitle, :string
    field :config_overrides, :map, default: %{}
    field :next_public_post_id, :integer, default: 1

    timestamps(type: :utc_datetime)
  end

  def changeset(board, attrs) do
    board
    |> cast(attrs, [:uri, :title, :subtitle, :config_overrides])
    |> validate_required([:uri, :title])
    |> update_change(:uri, &normalize_uri/1)
    |> validate_format(:uri, ~r/\A[a-zA-Z0-9_]+\z/)
    |> validate_length(:uri, min: 1, max: 32)
    |> validate_length(:title, min: 1, max: 255)
    |> unique_constraint(:uri)
  end

  def to_board(%__MODULE__{} = record) do
    %Board{
      id: record.id,
      uri: record.uri,
      title: record.title,
      subtitle: record.subtitle,
      name: record.title,
      config_overrides: Config.normalize_override_keys(record.config_overrides || %{})
    }
  end

  defp normalize_uri(uri) when is_binary(uri), do: uri |> String.trim() |> String.trim("/")
  defp normalize_uri(uri), do: uri
end
