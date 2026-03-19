defmodule EirinchanWeb.UploadedFileController do
  use EirinchanWeb, :controller

  alias Eirinchan.Uploads
  alias EirinchanWeb.CacheControl

  def show(conn, %{"board" => board, "filename" => filename}) do
    send_asset(conn, board, "src", filename)
  end

  def show_thumb(conn, %{"board" => board, "filename" => filename}) do
    send_asset(conn, board, "thumb", filename)
  end

  defp send_asset(conn, board, bucket, filename) do
    if filename != Path.basename(filename) do
      send_resp(conn, :not_found, "File not found")
    else
      path = Uploads.filesystem_path("/#{board}/#{bucket}/#{filename}")

      if File.exists?(path) do
        size = File.stat!(path).size

        conn
        |> put_resp_header("cache-control", CacheControl.cache_control_for_upload_bucket(bucket))
        |> put_resp_header("accept-ranges", "bytes")
        |> put_resp_content_type(MIME.from_path(path))
        |> maybe_send_ranged_file(path, size)
      else
        send_resp(conn, :not_found, "File not found")
      end
    end
  end

  defp maybe_send_ranged_file(conn, path, size) do
    case get_req_header(conn, "range") do
      [range_header | _] ->
        case parse_single_byte_range(range_header, size) do
          {:ok, first, last} ->
            length = last - first + 1

            conn
            |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
            |> put_resp_header("content-length", Integer.to_string(length))
            |> send_file(206, path, first, length)

          :error ->
            conn
            |> put_resp_header("content-range", "bytes */#{size}")
            |> send_resp(416, "")
        end

      _ ->
        send_file(conn, 200, path)
    end
  end

  defp parse_single_byte_range("bytes=" <> rest, size) do
    case String.split(rest, ",", parts: 2) do
      [single] -> parse_single_range_spec(String.trim(single), size)
      _ -> :error
    end
  end

  defp parse_single_byte_range(_, _size), do: :error

  defp parse_single_range_spec("-" <> suffix_text, size) do
    with {suffix, ""} <- Integer.parse(suffix_text),
         true <- suffix > 0 do
      length = min(suffix, size)
      first = size - length
      {:ok, first, size - 1}
    else
      _ -> :error
    end
  end

  defp parse_single_range_spec(spec, size) do
    case String.split(spec, "-", parts: 2) do
      [start_text, ""] ->
        with {start_offset, ""} <- Integer.parse(start_text),
             true <- start_offset >= 0 and start_offset < size do
          {:ok, start_offset, size - 1}
        else
          _ -> :error
        end

      [start_text, end_text] ->
        with {start_offset, ""} <- Integer.parse(start_text),
             {end_offset, ""} <- Integer.parse(end_text),
             true <- start_offset >= 0 and end_offset >= start_offset and start_offset < size do
          {:ok, start_offset, min(end_offset, size - 1)}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

end
