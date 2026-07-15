defmodule Eirinchan.StaticImageDimensions do
  @moduledoc false

  use GenServer

  @table __MODULE__
  @header_read_limit 256 * 1024
  @jpeg_sof_markers [
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    table =
      :ets.new(@table, [
        :named_table,
        :protected,
        :set,
        read_concurrency: true
      ])

    {:ok, table}
  end

  def for_static_path(path) when is_binary(path) do
    with {:ok, cache_key, file_path} <- resolve_static_path(path) do
      cached_or_load(cache_key, file_path)
    else
      _error -> nil
    end
  end

  def for_static_path(_path), do: nil

  def from_binary(<<
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        _length::32,
        "IHDR",
        width::32,
        height::32,
        _rest::binary
      >>),
      do: valid_dimensions(width, height)

  def from_binary(
        <<signature::binary-size(6), width::little-16, height::little-16, _rest::binary>>
      )
      when signature in ["GIF87a", "GIF89a"],
      do: valid_dimensions(width, height)

  def from_binary(<<0xFF, 0xD8, rest::binary>>), do: jpeg_dimensions(rest)
  def from_binary(_binary), do: nil

  @impl true
  def handle_call({:load, cache_key, file_path}, _from, table) do
    dimensions =
      case :ets.lookup(table, cache_key) do
        [{^cache_key, cached}] -> cached
        [] -> read_dimensions(file_path)
      end

    :ets.insert(table, {cache_key, dimensions})
    {:reply, dimensions, table}
  end

  defp cached_or_load(cache_key, file_path) do
    case :ets.whereis(@table) do
      :undefined ->
        read_dimensions(file_path)

      table ->
        case :ets.lookup(table, cache_key) do
          [{^cache_key, dimensions}] -> dimensions
          [] -> GenServer.call(__MODULE__, {:load, cache_key, file_path})
        end
    end
  end

  defp resolve_static_path(path) do
    uri = URI.parse(path)

    with nil <- uri.scheme,
         nil <- uri.host,
         decoded_path when is_binary(decoded_path) <- decode_path(uri.path),
         true <- String.starts_with?(decoded_path, "/"),
         false <- String.contains?(decoded_path, <<0>>),
         root <- Application.app_dir(:eirinchan, "priv/static") |> Path.expand(),
         relative <- String.trim_leading(decoded_path, "/"),
         file_path <- Path.expand(relative, root),
         safe_relative <- Path.relative_to(file_path, root),
         true <- safe_relative != ".",
         false <- safe_relative == ".." or String.starts_with?(safe_relative, "../"),
         true <- File.regular?(file_path) do
      {:ok, safe_relative, file_path}
    else
      _error -> :error
    end
  end

  defp decode_path(path) when is_binary(path) do
    URI.decode(path)
  rescue
    ArgumentError -> nil
  end

  defp decode_path(_path), do: nil

  defp read_dimensions(file_path) do
    case File.open(file_path, [:read, :binary], fn file ->
           IO.binread(file, @header_read_limit)
         end) do
      {:ok, binary} when is_binary(binary) -> from_binary(binary)
      _error -> nil
    end
  end

  defp jpeg_dimensions(<<0xFF, marker, _length::16, rest::binary>>)
       when marker in @jpeg_sof_markers do
    case rest do
      <<_precision, height::16, width::16, _rest::binary>> -> valid_dimensions(width, height)
      _rest -> nil
    end
  end

  defp jpeg_dimensions(<<0xFF, marker, length::16, rest::binary>>)
       when marker not in [0xD8, 0xD9, 0x01] and marker not in 0xD0..0xD7 do
    skip = max(length - 2, 0)

    if byte_size(rest) >= skip do
      <<_segment::binary-size(^skip), tail::binary>> = rest
      jpeg_dimensions(tail)
    end
  end

  defp jpeg_dimensions(<<_byte, rest::binary>>), do: jpeg_dimensions(rest)
  defp jpeg_dimensions(_binary), do: nil

  defp valid_dimensions(width, height)
       when is_integer(width) and width > 0 and is_integer(height) and height > 0,
       do: {width, height}

  defp valid_dimensions(_width, _height), do: nil
end
