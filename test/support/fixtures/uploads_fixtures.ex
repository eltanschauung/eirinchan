defmodule Eirinchan.UploadsFixtures do
  @avif_fixture_base64 "AAAAIGZ0eXBhdmlmAAAAAGF2aWZtaWYxbWlhZk1BMUEAAAD5bWV0YQAAAAAAAAAvaGRscgAAAAAAAAAAcGljdAAAAAAAAAAAAAAAAFBpY3R1cmVIYW5kbGVyAAAAAA5waXRtAAAAAAABAAAAHmlsb2MAAAAARAAAAQABAAAAAQAAASEAAAAlAAAAKGlpbmYAAAAAAAEAAAAaaW5mZQIAAAAAAQAAYXYwMUNvbG9yAAAAAGppcHJwAAAAS2lwY28AAAAUaXNwZQAAAAAAAAASAAAADAAAABBwaXhpAAAAAAMICAgAAAAMYXYxQ4EgAAAAAAATY29scm5jbHgAAgACAACAAAAAF2lwbWEAAAAAAAAAAQABBAECgwQAAAAtbWRhdAoMIAAAAhxs//mgIaAEMhUQAMAAAAKAAAARP5woQRO1PEyHf9I="
  @animated_webp_fixture_base64 "UklGRt4AAABXRUJQVlA4WAoAAAACAAAAEwAAEwAAQU5JTQYAAAD/////AABBTk1GWAAAAAAAAAAAABMAABMAAMgAAAJWUDggQAAAAFADAJ0BKhQAFAA+kUKcSiWjoqGoCACwEgllAMaqgABAURwAAP7upj/+xZy2BeP/+5wP+5wP+5wP42ykJ2cKAABBTk1GUgAAAAAAAAAAABMAABMAAMgAAABWUDggOgAAAJQCAJ0BKhQAFAA+kUKcSgKAgAABIJZQDMHBapagAP71WL//ucD//ZwP/9nA/jr/Xqlrk44Cy3gAAABSSUZGTAAAAFdFQlBWUDggQAAAAFADAJ0BKhQAFAA+kUKcSiWjoqGoCACwEgllAMaqgABAURwAAP7upj/+xZy2BeP/+5wP+5wP+5wP42ykJ2cKAAA="

  def upload_fixture(filename \\ "upload.png", content_or_opts \\ "fixture") do
    normalized_filename = filename |> to_string() |> String.trim()

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-upload-#{System.unique_integer([:positive])}-#{Path.basename(normalized_filename)}"
      )

    opts = normalize_opts(content_or_opts)

    case String.downcase(Path.extname(normalized_filename)) do
      ext when ext in [".png", ".jpg", ".jpeg", ".gif"] ->
        create_image!(path, opts)

      _ ->
        File.write!(path, opts.content)
    end

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: MIME.from_path(normalized_filename)
    }
  end

  def raw_upload_fixture(filename, content \\ "raw fixture") do
    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-upload-raw-#{System.unique_integer([:positive])}-#{Path.basename(filename)}"
      )

    File.write!(path, content)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: MIME.from_path(filename)
    }
  end

  def animated_gif_upload_fixture(filename \\ "animated.gif") do
    base =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-upload-anim-#{System.unique_integer([:positive])}-#{Path.basename(filename, ".gif")}"
      )

    frame1 = base <> "-f1.png"
    frame2 = base <> "-f2.png"
    gif_path = base <> ".gif"

    {_, 0} = System.cmd("convert", ["-size", "20x20", "xc:red", frame1])
    {_, 0} = System.cmd("convert", ["-size", "20x20", "xc:blue", frame2])
    {_, 0} = System.cmd("convert", ["-delay", "20", "-loop", "0", frame1, frame2, gif_path])

    %Plug.Upload{
      path: gif_path,
      filename: filename,
      content_type: "image/gif"
    }
  end

  def animated_webp_upload_fixture(filename \\ "animated.webp") do
    base =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-upload-anim-#{System.unique_integer([:positive])}-#{Path.basename(filename, ".webp")}"
      )

    webp_path = base <> ".webp"
    File.write!(webp_path, Base.decode64!(@animated_webp_fixture_base64))

    %Plug.Upload{
      path: webp_path,
      filename: filename,
      content_type: "image/webp"
    }
  end

  def avif_upload_fixture(filename \\ "sample.avif", _content_or_opts \\ "fixture") do
    base =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-upload-avif-#{System.unique_integer([:positive])}-#{Path.basename(filename, ".avif")}"
      )

    avif_path = base <> ".avif"
    File.write!(avif_path, Base.decode64!(@avif_fixture_base64))

    %Plug.Upload{
      path: avif_path,
      filename: filename,
      content_type: "image/avif"
    }
  end

  def video_upload_fixture(filename \\ "sample.mp4", opts \\ []) do
    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-upload-video-#{System.unique_integer([:positive])}-#{Path.basename(filename)}"
      )

    ext = filename |> Path.extname() |> String.downcase()
    video_codec = if ext == ".webm", do: "libvpx-vp9", else: "libx264"
    pixel_format = if ext == ".webm", do: [], else: ["-pix_fmt", "yuv420p"]
    geometry = Keyword.get(opts, :geometry, "64x48")
    duration = Keyword.get(opts, :duration, 1)

    args =
      [
        "-y",
        "-f",
        "lavfi",
        "-i",
        "color=c=red:s=#{geometry}:d=#{duration}",
        "-f",
        "lavfi",
        "-i",
        "anullsrc=channel_layout=mono:sample_rate=44100",
        "-shortest",
        "-c:v",
        video_codec
      ] ++ pixel_format ++ ["-an", path]

    {_, 0} = System.cmd("ffmpeg", args, stderr_to_stdout: true)

    %Plug.Upload{
      path: path,
      filename: filename,
      content_type: MIME.from_path(filename)
    }
  end

  def duplicate_upload_fixture(%Plug.Upload{} = upload, filename \\ nil) do
    duplicate_name = filename || upload.filename

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-upload-dup-#{System.unique_integer([:positive])}-#{Path.basename(duplicate_name)}"
      )

    File.cp!(upload.path, path)

    %Plug.Upload{
      path: path,
      filename: duplicate_name,
      content_type: upload.content_type
    }
  end

  def serve_upload_fixture(body, filename, opts \\ []) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, {_address, port}} = :inet.sockname(listen_socket)
    content_type = Keyword.get(opts, :content_type, MIME.from_path(filename))

    {:ok, task} =
      Task.start_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        _ = :gen_tcp.recv(socket, 0)

        response = [
          "HTTP/1.1 200 OK\r\n",
          "Content-Length: #{byte_size(body)}\r\n",
          "Content-Type: #{content_type}\r\n",
          "Connection: close\r\n\r\n",
          body
        ]

        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        :gen_tcp.close(listen_socket)
      end)

    %{
      url: "http://127.0.0.1:#{port}/#{filename}",
      stop: fn ->
        _ = :gen_tcp.close(listen_socket)

        if Process.alive?(task) do
          Process.exit(task, :kill)
        end

        :ok
      end
    }
  end

  def serve_stalled_upload(filename \\ "stall.png", opts \\ []) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, {_address, port}} = :inet.sockname(listen_socket)
    delay_ms = Keyword.get(opts, :delay_ms, 500)

    {:ok, task} =
      Task.start_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        _ = :gen_tcp.recv(socket, 0)
        Process.sleep(delay_ms)
        :gen_tcp.close(socket)
        :gen_tcp.close(listen_socket)
      end)

    %{
      url: "http://127.0.0.1:#{port}/#{filename}",
      stop: fn ->
        _ = :gen_tcp.close(listen_socket)

        if Process.alive?(task) do
          Process.exit(task, :kill)
        end

        :ok
      end
    }
  end

  def serve_json_response(body, opts \\ []) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, {_address, port}} = :inet.sockname(listen_socket)
    status_line = Keyword.get(opts, :status_line, "HTTP/1.1 200 OK")

    {:ok, task} =
      Task.start_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        _ = :gen_tcp.recv(socket, 0)

        response = [
          status_line,
          "\r\n",
          "Content-Length: #{byte_size(body)}\r\n",
          "Content-Type: application/json\r\n",
          "Connection: close\r\n\r\n",
          body
        ]

        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        :gen_tcp.close(listen_socket)
      end)

    %{
      url: "http://127.0.0.1:#{port}/verify",
      stop: fn ->
        _ = :gen_tcp.close(listen_socket)

        if Process.alive?(task) do
          Process.exit(task, :kill)
        end

        :ok
      end
    }
  end

  defp normalize_opts(opts) when is_list(opts) do
    %{
      content: to_string(Keyword.get(opts, :content, "fixture")),
      geometry: Keyword.get(opts, :geometry, "16x16"),
      artist: Keyword.get(opts, :artist),
      orientation: Keyword.get(opts, :orientation)
    }
  end

  defp normalize_opts(content) do
    %{content: to_string(content), geometry: "16x16", artist: nil, orientation: nil}
  end

  defp create_image!(path, opts) do
    color =
      :crypto.hash(:md5, opts.content)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 6)
      |> then(&"##{&1}")

    convert_args =
      ["-size", opts.geometry, "xc:#{color}"] ++
        if(is_binary(opts.artist), do: ["-set", "comment", opts.artist], else: []) ++ [path]

    {_, 0} = System.cmd("convert", convert_args)

    if is_binary(opts.artist) do
      {_, 0} = System.cmd("exiftool", ["-overwrite_original", "-Artist=#{opts.artist}", path])
    end

    if is_binary(opts.orientation) do
      {_, 0} =
        System.cmd("exiftool", ["-overwrite_original", "-Orientation=#{opts.orientation}", path])
    end

    path
  end
end
