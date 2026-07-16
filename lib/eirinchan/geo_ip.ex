defmodule Eirinchan.GeoIp do
  @moduledoc """
  GeoIP2 country lookup backed by a locally managed MaxMind MMDB.

  Locus watches local database sources and reloads changed files automatically.
  """

  @loader_id :eirinchan_geoip2_country
  @loader_key {__MODULE__, :loader_path}
  @validation_key {__MODULE__, :database_validation}
  @metadata_marker <<0xAB, 0xCD, 0xEF, "MaxMind.com">>
  @metadata_search_bytes 131_072

  @spec lookup_country(term(), map()) :: {:ok, %{code: binary(), name: binary()}} | :error
  def lookup_country(nil, _config), do: :error

  def lookup_country(remote_ip, config) do
    database_path = config[:geoip2_database_path]

    cond do
      not is_binary(database_path) or String.trim(database_path) == "" ->
        :error

      not valid_database_file?(database_path) ->
        :error

      true ->
        with {:ok, loader} <- ensure_loader(database_path),
             {:ok, info} <- :locus.lookup(loader, to_string(remote_ip)),
             {:ok, metadata} <- country_metadata(info) do
          {:ok, metadata}
        else
          _ -> :error
        end
    end
  end

  defp valid_database_file?(database_path) do
    with {:ok, %{type: :regular, size: size, mtime: mtime, inode: inode}} <-
           File.stat(database_path),
         true <- size >= byte_size(@metadata_marker) do
      signature = {database_path, size, mtime, inode}

      case :persistent_term.get(@validation_key, nil) do
        {^signature, valid?} ->
          valid?

        _ ->
          valid? = contains_metadata_marker?(database_path, size)
          :persistent_term.put(@validation_key, {signature, valid?})
          valid?
      end
    else
      _ -> false
    end
  end

  defp contains_metadata_marker?(database_path, size) do
    offset = max(size - @metadata_search_bytes, 0)

    with {:ok, file} <- File.open(database_path, [:read, :binary]) do
      try do
        case :file.pread(file, offset, size - offset) do
          {:ok, data} -> :binary.match(data, @metadata_marker) != :nomatch
          _ -> false
        end
      after
        File.close(file)
      end
    else
      _ -> false
    end
  end

  defp ensure_loader(database_path) do
    current_path = :persistent_term.get(@loader_key, nil)

    if current_path == database_path do
      {:ok, @loader_id}
    else
      maybe_stop_loader()

      case :locus.start_loader(@loader_id, database_path) do
        :ok ->
          await_loader(database_path)

        {:ok, _pid} ->
          await_loader(database_path)

        {:error, {:already_started, _pid}} ->
          await_loader(database_path)

        {:error, :already_started} ->
          await_loader(database_path)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp await_loader(database_path) do
    case :locus.await_loader(@loader_id) do
      :ok ->
        :persistent_term.put(@loader_key, database_path)
        {:ok, @loader_id}

      {:ok, _loader_info} ->
        :persistent_term.put(@loader_key, database_path)
        {:ok, @loader_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_stop_loader do
    case :locus.stop_loader(@loader_id) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end

    :persistent_term.erase(@loader_key)
    :ok
  end

  defp country_metadata(info) do
    country =
      Map.get(info, :country) ||
        Map.get(info, "country")

    with code when not is_nil(code) <- value_in(country, [:iso_code, "iso_code"]),
         name when not is_nil(name) <- english_name(country) do
      {:ok, %{code: String.downcase(to_string(code)), name: to_string(name)}}
    else
      _ -> :error
    end
  end

  defp english_name(country) do
    names =
      value_in(country, [:names, "names"])

    value_in(names, [:en, "en"])
  end

  defp value_in(nil, _keys), do: nil

  defp value_in(map, keys) when is_map(map) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp value_in(_other, _keys), do: nil
end
