defmodule Eirinchan.PrimaryBoard do
  @moduledoc false

  @default_uri "b"
  @valid_uri ~r/\A[a-zA-Z0-9_]+\z/

  def default_uri, do: @default_uri

  def uri(config) when is_map(config) do
    config
    |> Map.get(:primary_board_uri, Map.get(config, "primary_board_uri", @default_uri))
    |> normalize_uri()
  end

  def uri(_config), do: @default_uri

  def normalize_uri(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.trim("/")

    if byte_size(normalized) in 1..32 and Regex.match?(@valid_uri, normalized),
      do: normalized,
      else: @default_uri
  end

  def normalize_uri(_value), do: @default_uri

  def find(boards, config) when is_list(boards) do
    configured_uri = uri(config)
    Enum.find(boards, &(&1.uri == configured_uri)) || List.first(boards)
  end

  def find(_boards, _config), do: nil

  def resolve(boards, config) do
    find(boards, config) || %{uri: uri(config)}
  end
end
