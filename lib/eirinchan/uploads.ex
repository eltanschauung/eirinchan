defmodule Eirinchan.Uploads do
  @moduledoc """
  Minimal single-file upload storage backed by the board build directory.
  """

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post

  @image_extensions [".png", ".jpg", ".jpeg", ".gif"]

  @spec describe(Plug.Upload.t(), map()) :: {:ok, map()} | {:error, atom()}
  def describe(%Plug.Upload{} = upload, config) do
    normalized_name = normalized_input_filename(upload.filename)

    with {:ok, binary} <- File.read(upload.path) do
      ext =
        normalized_name
        |> Path.extname()
        |> String.downcase()

      file_type = detect_mime_type(upload.path, normalized_name)
      image_metadata = maybe_image_metadata(upload.path, file_type)

      metadata = %{
        binary: binary,
        ext: ext,
        file_name: normalized_filename(normalized_name, config),
        file_size: byte_size(binary),
        file_type: file_type,
        file_md5: :crypto.hash(:md5, binary) |> Base.encode64(),
        image_width: image_metadata.width,
        image_height: image_metadata.height,
        spoiler: false
      }

      normalized_upload_metadata(upload.path, metadata)
    else
      {:error, _reason} -> {:error, :upload_failed}
    end
  end

  @spec store(BoardRecord.t(), Post.t(), Plug.Upload.t(), map()) ::
          {:ok, map()} | {:error, atom()}
  def store(%BoardRecord{} = board, %Post{} = post, %Plug.Upload{} = upload, config) do
    with {:ok, metadata} <- describe(upload, config) do
      store(board, post, upload, config, metadata, nil)
    end
  end

  @spec store(BoardRecord.t(), Post.t(), Plug.Upload.t(), map(), map()) ::
          {:ok, map()} | {:error, atom()}
  def store(%BoardRecord{} = board, %Post{} = post, %Plug.Upload{} = upload, config, metadata) do
    store(board, post, upload, config, metadata, nil)
  end

  @spec store(BoardRecord.t(), Post.t(), Plug.Upload.t(), map(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, atom()}
  def store(
        %BoardRecord{} = board,
        %Post{} = post,
        %Plug.Upload{} = upload,
        config,
        metadata,
        suffix
      ) do
    base_name = unique_timestamp_base_name(board, post, config, metadata.ext, suffix)
    storage_name = "#{base_name}#{metadata.ext}"
    destination = Path.join([board_root(), board.uri, config.dir.img, storage_name])
    thumb_name = "#{base_name}s.png"
    thumb_destination = Path.join([board_root(), board.uri, config.dir.thumb, thumb_name])

    destination
    |> Path.dirname()
    |> File.mkdir_p!()

    thumb_destination
    |> Path.dirname()
    |> File.mkdir_p!()

    case move_to_destination(upload.path, destination) do
      :ok ->
        with :ok <- normalize_stored_upload(destination, config, metadata),
             {:ok, stored_metadata} <- refresh_stored_metadata(destination, metadata),
             :ok <-
               generate_thumbnail(
                 destination,
                 thumb_destination,
                 config,
                 stored_metadata,
                 is_nil(post.thread_id)
               ) do
          {:ok,
           Map.merge(stored_metadata, %{
             file_path: "/#{board.uri}/#{config.dir.img}#{storage_name}",
             thumb_path: "/#{board.uri}/#{config.dir.thumb}#{thumb_name}"
           })}
        else
          {:error, reason} ->
            _ = File.rm(destination)
            _ = File.rm(thumb_destination)
            {:error, reason}
        end

      {:error, _reason} ->
        {:error, :upload_failed}
    end
  end

  @spec remove(String.t() | nil) :: :ok
  def remove(nil), do: :ok

  def remove(file_path) when is_binary(file_path) do
    _ = File.rm(filesystem_path(file_path))
    :ok
  end

  @spec relocate(String.t() | nil, String.t() | nil) :: :ok | {:error, atom()}
  def relocate(nil, nil), do: :ok
  def relocate(path, path) when is_binary(path), do: :ok
  def relocate(nil, _destination), do: :ok

  def relocate(source_path, destination_path)
      when is_binary(source_path) and is_binary(destination_path) do
    source = filesystem_path(source_path)
    destination = filesystem_path(destination_path)

    if source == destination do
      :ok
    else
      destination
      |> Path.dirname()
      |> File.mkdir_p!()

      case move_to_destination(source, destination) do
        :ok -> :ok
        {:error, _reason} -> {:error, :upload_failed}
      end
    end
  end

  @spec filesystem_path(String.t()) :: String.t()
  def filesystem_path(file_path) do
    sanitized =
      file_path
      |> String.trim_leading("/")
      |> Path.split()
      |> Enum.reject(&(&1 in [".", ".."]))

    Path.join([board_root() | sanitized])
  end

  @spec write_spoiler_thumbnail(String.t() | nil, map()) :: :ok | {:error, atom()}
  def write_spoiler_thumbnail(nil, _config), do: :ok

  def write_spoiler_thumbnail(file_path, config) when is_binary(file_path) do
    destination = filesystem_path(file_path)
    Path.dirname(destination) |> File.mkdir_p!()
    generate_spoiler_thumbnail(destination, config)
  end

  @spec board_root() :: String.t()
  def board_root do
    Application.fetch_env!(:eirinchan, :build_output_root)
  end

  def image?(%{file_type: file_type}) when is_binary(file_type),
    do: String.starts_with?(file_type, "image/")

  def image?(_metadata), do: false

  def compatible_with_extension?(%{ext: ext, file_type: file_type}),
    do: compatible_with_extension?(ext, file_type)

  def compatible_with_extension?(ext, file_type)
      when is_binary(ext) and is_binary(file_type) do
    cond do
      ext in [".jpg", ".jpeg"] -> file_type == "image/jpeg"
      ext == ".png" -> file_type == "image/png"
      ext == ".gif" -> file_type == "image/gif"
      ext == ".txt" -> file_type == "inode/x-empty" or String.starts_with?(file_type, "text/")
      true -> true
    end
  end

  def compatible_with_extension?(_ext, _file_type), do: false

  def image_extension?(ext) when is_binary(ext), do: ext in @image_extensions
  def image_extension?(_ext), do: false

  @spec fetch_remote_upload(String.t(), map()) :: {:ok, Plug.Upload.t()} | {:error, atom()}
  def fetch_remote_upload(url, config) when is_binary(url) do
    try do
      Process.put(:eirinchan_upload_remote_config, config)

      with {:ok, uri} <- normalize_remote_uri(url),
           :ok <- ensure_http_client(),
           {:ok, body, headers} <- download_remote_body(uri, config) do
        write_remote_upload(uri, headers, body)
      end
    after
      Process.delete(:eirinchan_upload_remote_config)
    end
  end

  def fetch_remote_upload(_url, _config), do: {:error, :upload_failed}

  defp maybe_image_metadata(path, file_type) do
    if String.starts_with?(file_type, "image/") do
      case image_metadata(path) do
        {:ok, data} -> data
        {:error, :invalid_image} -> %{width: nil, height: nil}
      end
    else
      %{width: nil, height: nil}
    end
  end

  defp detect_mime_type(path, normalized_name) do
    case System.cmd("file", ["--mime-type", "-b", path], stderr_to_stdout: true) do
      {output, 0} ->
        case String.trim(output) do
          "" -> MIME.from_path(normalized_name)
          mime_type -> mime_type
        end

      _ ->
        MIME.from_path(normalized_name)
    end
  end

  defp move_to_destination(source, destination) do
    case rename_upload(source, destination) do
      :ok ->
        _ = File.chmod(destination, 0o644)
        :ok

      {:error, _reason} ->
        case File.cp(source, destination) do
          :ok ->
            _ = File.rm(source)
            _ = File.chmod(destination, 0o644)
            :ok

          {:error, _copy_reason} ->
            {:error, :upload_failed}
        end
    end
  end

  defp rename_upload(source, destination) do
    if Process.get(:eirinchan_force_rename_failure) do
      {:error, :forced}
    else
      File.rename(source, destination)
    end
  end

  defp timestamp_base_name(post, suffix) do
    timestamp =
      post
      |> post_timestamp()
      |> DateTime.to_unix(:millisecond)
      |> Integer.to_string()

    base = timestamp

    if is_binary(suffix), do: "#{base}-#{suffix}", else: base
  end

  defp unique_timestamp_base_name(board, post, config, ext, suffix) do
    timestamp =
      post
      |> post_timestamp()
      |> DateTime.to_unix(:millisecond)

    resolve_timestamp_base_name(board, config, timestamp, ext, suffix)
  end

  defp resolve_timestamp_base_name(board, config, timestamp, ext, suffix) do
    base =
      timestamp
      |> Integer.to_string()
      |> then(fn value -> if is_binary(suffix), do: "#{value}-#{suffix}", else: value end)

    img_path = Path.join([board_root(), board.uri, config.dir.img, "#{base}#{ext}"])
    thumb_path = Path.join([board_root(), board.uri, config.dir.thumb, "#{base}s.png"])

    if File.exists?(img_path) or File.exists?(thumb_path) do
      resolve_timestamp_base_name(board, config, timestamp + 1, ext, suffix)
    else
      base
    end
  end

  defp post_timestamp(%Post{inserted_at: %DateTime{} = inserted_at}), do: inserted_at

  defp post_timestamp(%Post{inserted_at: %NaiveDateTime{} = inserted_at}),
    do: DateTime.from_naive!(inserted_at, "Etc/UTC")

  defp post_timestamp(_post), do: DateTime.utc_now()

  defp normalize_remote_uri(url) do
    uri = url |> String.trim() |> URI.parse()
    config = Process.get(:eirinchan_upload_remote_config, %{})

    cond do
      uri.scheme not in ["http", "https"] -> {:error, :upload_failed}
      not is_binary(uri.host) -> {:error, :upload_failed}
      remote_host_allowed?(uri.host, config) -> {:ok, uri}
      true -> {:error, :upload_failed}
    end
  end

  defp ensure_http_client do
    _ = :inets.start()
    _ = :ssl.start()
    :ok
  end

  defp download_remote_body(uri, config) do
    timeout = config[:upload_by_url_timeout_ms] || 5_000
    max_filesize = config[:max_filesize] || 10 * 1024 * 1024
    request = {String.to_charlist(URI.to_string(uri)), []}
    http_options = [timeout: timeout, connect_timeout: timeout, autoredirect: true]

    case :httpc.request(:get, request, http_options, body_format: :binary) do
      {:ok, {{_version, 200, _reason}, headers, body}} ->
        if remote_body_too_large?(headers, body, max_filesize) do
          {:error, :upload_failed}
        else
          {:ok, body, headers}
        end

      {:ok, {{_version, _status, _reason}, _headers, _body}} ->
        {:error, :upload_failed}

      {:error, _reason} ->
        {:error, :upload_failed}
    end
  end

  defp write_remote_upload(uri, headers, body) when is_binary(body) do
    filename = remote_filename(uri, headers)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-remote-upload-#{System.unique_integer([:positive])}-#{Path.basename(filename)}"
      )

    case File.write(path, body) do
      :ok ->
        {:ok,
         %Plug.Upload{
           path: path,
           filename: filename,
           content_type: remote_content_type(headers, filename)
         }}

      {:error, _reason} ->
        {:error, :upload_failed}
    end
  end

  defp remote_filename(uri, headers) do
    from_disposition = header_filename(headers)

    candidate =
      cond do
        is_binary(from_disposition) and from_disposition != "" ->
          from_disposition

        is_binary(uri.path) and uri.path not in [nil, "/"] ->
          uri.path |> Path.basename() |> URI.decode()

        true ->
          "remote-upload"
      end

    if Path.extname(candidate) == "" do
      case MIME.extensions(remote_content_type(headers, candidate)) do
        [ext | _rest] -> "#{candidate}.#{ext}"
        _ -> candidate
      end
    else
      candidate
    end
  end

  defp remote_content_type(headers, filename) do
    header_value(headers, "content-type") || MIME.from_path(filename)
  end

  defp remote_body_too_large?(headers, body, max_filesize) when is_integer(max_filesize) do
    content_length =
      case header_value(headers, "content-length") do
        nil ->
          nil

        value ->
          case Integer.parse(value) do
            {parsed, _rest} -> parsed
            :error -> nil
          end
      end

    body_size = byte_size(body)

    (is_integer(content_length) and content_length > max_filesize) or body_size > max_filesize
  end

  defp remote_host_allowed?(host, config) do
    if Map.get(config, :upload_by_url_allow_private_hosts, false) do
      true
    else
      do_remote_host_allowed?(host)
    end
  end

  defp do_remote_host_allowed?(host) do
    case parse_literal_ip(host) do
      {:ok, address} ->
        not private_or_local_address?(address)

      :error ->
        dns_host_allowed?(host)
    end
  end

  defp parse_literal_ip(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} -> {:ok, address}
      {:error, _reason} -> :error
    end
  end

  defp dns_host_allowed?(host) do
    normalized = String.downcase(host)

    cond do
      normalized in ["localhost", "localhost.localdomain"] -> false
      String.ends_with?(normalized, ".localhost") -> false
      true ->
        [resolve_addresses(host, :inet), resolve_addresses(host, :inet6)]
        |> List.flatten()
        |> case do
          [] -> false
          addresses -> Enum.all?(addresses, &(not private_or_local_address?(&1)))
        end
    end
  end

  defp resolve_addresses(host, family) do
    case :inet.getaddrs(String.to_charlist(host), family) do
      {:ok, addresses} -> addresses
      {:error, _reason} -> []
    end
  end

  defp private_or_local_address?({127, _, _, _}), do: true
  defp private_or_local_address?({10, _, _, _}), do: true
  defp private_or_local_address?({192, 168, _, _}), do: true
  defp private_or_local_address?({172, second, _, _}) when second in 16..31, do: true
  defp private_or_local_address?({169, 254, _, _}), do: true
  defp private_or_local_address?({0, _, _, _}), do: true
  defp private_or_local_address?({100, second, _, _}) when second in 64..127, do: true
  defp private_or_local_address?({192, 0, 0, _}), do: true
  defp private_or_local_address?({198, 18, _, _}), do: true
  defp private_or_local_address?({198, 19, _, _}), do: true
  defp private_or_local_address?({224, _, _, _}), do: true
  defp private_or_local_address?({255, _, _, _}), do: true
  defp private_or_local_address?({_a, _b, _c, _d}), do: false

  defp private_or_local_address?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp private_or_local_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_or_local_address?({0, 0, 0, 0, 0, 65_535, _, _}), do: true
  defp private_or_local_address?({0, 0, 0, 0, 0, 16_383, _, _}), do: true
  defp private_or_local_address?({first, _, _, _, _, _, _, _}) when first in 64_512..65_023,
    do: true
  defp private_or_local_address?({first, _, _, _, _, _, _, _}) when first in 65_024..65_535,
    do: true
  defp private_or_local_address?({_a, _b, _c, _d, _e, _f, _g, _h}), do: false

  defp header_filename(headers) do
    case header_value(headers, "content-disposition") do
      nil ->
        nil

      disposition ->
        case Regex.run(~r/filename="?([^\";]+)"?/, disposition, capture: :all_but_first) do
          [filename] -> filename
          _ -> nil
        end
    end
  end

  defp header_value(headers, header_name) do
    Enum.find_value(headers, fn
      {key, value} ->
        if String.downcase(to_string(key)) == header_name do
          to_string(value)
        end
    end)
  end

  defp normalize_stored_upload(path, _config, metadata) do
    if image?(metadata) do
      case System.cmd("mogrify", ["-auto-orient", "-strip", path], stderr_to_stdout: true) do
        {_output, 0} -> :ok
        _ -> {:error, :upload_failed}
      end
    else
      :ok
    end
  end

  defp normalized_upload_metadata(path, metadata) do
    if image?(metadata) do
      temp_path = "#{path}.normalized"

      with :ok <- File.cp(path, temp_path),
           :ok <- normalize_stored_upload(temp_path, %{}, metadata),
           {:ok, normalized} <- refresh_stored_metadata(temp_path, metadata) do
        _ = File.rm(temp_path)
        {:ok, normalized}
      else
        {:error, reason} ->
          _ = File.rm(temp_path)
          {:error, reason}
      end
    else
      {:ok, metadata}
    end
  end

  defp refresh_stored_metadata(path, metadata) do
    with {:ok, binary} <- File.read(path) do
      file_type = detect_mime_type(path, metadata.file_name)
      image_metadata = maybe_image_metadata(path, file_type)

      {:ok,
       metadata
       |> Map.put(:binary, binary)
       |> Map.put(:file_size, byte_size(binary))
       |> Map.put(:file_type, file_type)
       |> Map.put(:file_md5, :crypto.hash(:md5, binary) |> Base.encode64())
       |> Map.put(:image_width, image_metadata.width)
       |> Map.put(:image_height, image_metadata.height)}
    else
      {:error, _reason} -> {:error, :upload_failed}
    end
  end

  defp image_metadata(path) do
    case System.cmd("identify", ["-format", "%w %h", first_frame_path(path)], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.scan(~r/\d+/, output) |> Enum.map(&hd/1) do
          [width, height | _rest] ->
            {:ok, %{width: String.to_integer(width), height: String.to_integer(height)}}

          _ ->
            {:error, :invalid_image}
        end

      _ ->
        {:error, :invalid_image}
    end
  end

  defp generate_thumbnail(source, destination, config, metadata, op?) do
    cond do
      Map.get(metadata, :spoiler) ->
        generate_spoiler_thumbnail(destination, config)

      image?(metadata) ->
        generate_image_thumbnail(source, destination, config, op?)

      true ->
        generate_placeholder_thumbnail(destination, config, metadata)
    end
  end

  defp generate_image_thumbnail(source, destination, config, op?) do
    if minimum_copy_resize?(source, config) do
      case File.cp(source, destination) do
        :ok -> :ok
        {:error, _reason} -> {:error, :upload_failed}
      end
    else
      geometry = image_thumbnail_geometry(config, op?)

      case System.cmd(
             "convert",
             [first_frame_path(source), "-auto-orient", "-thumbnail", geometry, destination],
             stderr_to_stdout: true
           ) do
        {_output, 0} -> :ok
        _ -> {:error, :upload_failed}
      end
    end
  end

  defp first_frame_path(path) when is_binary(path) do
    if String.downcase(Path.extname(path)) == ".gif" do
      path <> "[0]"
    else
      path
    end
  end

  defp image_thumbnail_geometry(config, true),
    do: "#{config.thumb_op_width}x#{config.thumb_op_height}"

  defp image_thumbnail_geometry(config, false),
    do: "#{config.thumb_width}x#{config.thumb_height}"

  defp minimum_copy_resize?(source, config) do
    config.minimum_copy_resize and
      Path.extname(source) == ".png" and
      case image_metadata(source) do
        {:ok, %{width: width, height: height}} ->
          width <= config.thumb_width and height <= config.thumb_height

        _ ->
          false
      end
  end

  defp generate_placeholder_thumbnail(destination, config, metadata) do
    case file_icon_source(config, metadata) do
      nil ->
        generate_placeholder_label_thumbnail(destination, config, metadata)

      icon_source ->
        case File.cp(icon_source, destination) do
          :ok -> :ok
          {:error, _reason} -> {:error, :upload_failed}
        end
    end
  end

  defp generate_placeholder_label_thumbnail(destination, config, metadata) do
    size = "#{config.thumb_width}x#{config.thumb_height}"

    label =
      metadata.file_name
      |> Path.extname()
      |> String.trim_leading(".")
      |> String.upcase()
      |> case do
        "" -> "FILE"
        ext -> ext
      end

    case System.cmd(
           "convert",
           [
             "-size",
             size,
             "xc:#f1ede3",
             "-fill",
             "#3b3426",
             "-gravity",
             "center",
             "-pointsize",
             "28",
             "-annotate",
             "0",
             label,
             destination
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      _ -> {:error, :upload_failed}
    end
  end

  defp file_icon_source(config, metadata) do
    ext = metadata.ext || ""
    ext_without_dot = String.trim_leading(ext, ".")

    icon_name =
      Map.get(config.file_icons || %{}, ext) ||
        Map.get(config.file_icons || %{}, ext_without_dot) ||
        Map.get(config.file_icons || %{}, "default")

    cond do
      not is_binary(icon_name) ->
        nil

      is_binary(config.file_thumb) and String.contains?(config.file_thumb, "%s") ->
        path = String.replace(config.file_thumb, "%s", icon_name)
        if File.exists?(path), do: path, else: nil

      is_binary(icon_name) and File.exists?(icon_name) ->
        icon_name

      true ->
        nil
    end
  end

  defp generate_spoiler_thumbnail(destination, config) do
    size = "#{config.thumb_width}x#{config.thumb_height}"

    case System.cmd(
           "convert",
           [
             "-size",
             size,
             "xc:#202020",
             "-fill",
             "#f0f0f0",
             "-gravity",
             "center",
             "-pointsize",
             "26",
             "-annotate",
             "0",
             "SPOILER",
             destination
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      _ -> {:error, :upload_failed}
    end
  end

  defp normalized_filename(filename, config) do
    original_ext = Path.extname(filename)

    ext =
      filename
      |> Path.extname()
      |> String.downcase()

    max_length = max(config.max_filename_display_length || 64, 1)

    base =
      filename
      |> Path.basename(original_ext)
      |> String.trim()
      |> String.replace(~r/[[:cntrl:]]+/u, "")
      |> String.replace(~r/[^A-Za-z0-9._-]+/u, "_")
      |> String.trim("_")
      |> case do
        "" -> "file"
        sanitized -> sanitized
      end
      |> String.slice(0, max_length)

    base <> ext
  end

  defp normalized_input_filename(filename) do
    filename
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "file"
      trimmed -> trimmed
    end
  end
end
