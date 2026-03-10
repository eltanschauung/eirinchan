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
        conn
        |> put_resp_header("cache-control", CacheControl.cache_control_for_path(path))
        |> put_resp_content_type(MIME.from_path(path))
        |> send_file(200, path)
      else
        send_resp(conn, :not_found, "File not found")
      end
    end
  end

end
