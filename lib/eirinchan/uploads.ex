defmodule Eirinchan.Uploads do
  @moduledoc """
  Minimal single-file upload storage backed by the board build directory.
  """

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post

  @image_extensions [".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp"]
  @video_extensions [".webm", ".mp4"]
  @jpeg_thumbnail_quality 85

  @spec describe(Plug.Upload.t(), map()) :: {:ok, map()} | {:error, atom()}
  def describe(%Plug.Upload{} = upload, config) do
    normalized_name = normalized_input_filename(upload.filename)

    with {:ok, digest} <- file_digest_metadata(upload.path) do
      ext = normalized_name |> Path.extname() |> String.downcase()
      file_type = detect_mime_type(upload.path, normalized_name)
      normalized_ext = normalized_media_extension(ext, file_type)
      media_metadata = maybe_media_metadata(upload.path, file_type, normalized_ext, config)

      metadata = %{
        binary: digest.prefix,
        ext: normalized_ext,
        file_name: normalized_filename(normalized_name, config),
        file_size: digest.size,
        file_type: file_type,
        file_md5: digest.md5,
        image_width: media_metadata.width,
        image_height: media_metadata.height,
        spoiler: false
      }

      normalized_upload_metadata(upload.path, metadata, config)
    else
      {:error, _reason} -> {:error, :upload_failed}
    end
  end

  @spec prepare(Plug.Upload.t(), map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def prepare(%Plug.Upload{} = upload, config, opts \\ []) do
    op? = Keyword.get(opts, :op?, false)
    normalized_name = normalized_input_filename(upload.filename)

    with :ok <- validate_upload_size_early(upload, config),
         {:ok, initial_metadata} <- describe_without_normalizing(upload, normalized_name, config),
         {:ok, staged_path} <- create_staged_upload_path(initial_metadata.ext) do
      with :ok <- File.cp(upload.path, staged_path),
           :ok <- normalize_stored_upload(staged_path, config, initial_metadata),
           {:ok, prepared_metadata} <- refresh_stored_metadata(staged_path, initial_metadata, config),
           {:ok, staged_thumb_path} <-
             create_staged_thumbnail_path(thumbnail_extension(prepared_metadata, config)) do
        case generate_thumbnail(staged_path, staged_thumb_path, config, prepared_metadata, op?) do
          :ok ->
            {:ok,
             prepared_metadata
             |> Map.put(:prepared_upload, true)
             |> Map.put(:staged_path, staged_path)
             |> Map.put(:source_upload_path, upload.path)
             |> Map.put(:staged_thumb_path, staged_thumb_path)}

          {:error, reason} ->
            cleanup_prepared(%{staged_path: staged_path, staged_thumb_path: staged_thumb_path})
            {:error, reason}
        end
      else
        {:error, reason} ->
          cleanup_prepared(%{staged_path: staged_path})
          {:error, reason}
      end
    end
  end

  @spec store(BoardRecord.t(), Post.t(), Plug.Upload.t(), map()) ::
          {:ok, map()} | {:error, atom()}
  def store(%BoardRecord{} = board, %Post{} = post, %Plug.Upload{} = upload, config) do
    with {:ok, metadata} <- prepare(upload, config, op?: is_nil(post.thread_id)) do
      finalize(board, post, config, metadata, nil)
    end
  end

  @spec store(BoardRecord.t(), Post.t(), Plug.Upload.t(), map(), map()) ::
          {:ok, map()} | {:error, atom()}
  def store(%BoardRecord{} = board, %Post{} = post, %Plug.Upload{} = upload, config, metadata) do
    _ = upload
    finalize(board, post, config, metadata, nil)
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
    _ = upload
    finalize(board, post, config, metadata, suffix)
  end

  defp validate_upload_size_early(%Plug.Upload{path: path}, config) do
    max_filesize = config[:max_filesize] || 10 * 1024 * 1024

    if is_integer(max_filesize) and max_filesize > 0 do
      case File.stat(path) do
        {:ok, %{size: size}} when size > max_filesize -> {:error, :file_too_large}
        {:ok, _stat} -> :ok
        {:error, _reason} -> {:error, :upload_failed}
      end
    else
      :ok
    end
  end

  @spec finalize(BoardRecord.t(), Post.t(), map(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, atom()}
  def finalize(
        %BoardRecord{} = board,
        %Post{} = post,
        config,
        metadata,
        suffix \\ nil
      ) do
    base_name = unique_timestamp_base_name(board, post, config, metadata.ext, suffix)
    storage_name = "#{base_name}#{metadata.ext}"
    destination = Path.join([board_root(), board.uri, config.dir.img, storage_name])
    thumb_ext = thumbnail_extension(metadata, config)
    thumb_name = "#{base_name}s#{thumb_ext}"
    thumb_destination = Path.join([board_root(), board.uri, config.dir.thumb, thumb_name])

    destination
    |> Path.dirname()
    |> File.mkdir_p!()

    thumb_destination
    |> Path.dirname()
    |> File.mkdir_p!()

    case move_to_destination(Map.get(metadata, :staged_path), destination) do
      :ok ->
        with :ok <- move_to_destination(Map.get(metadata, :staged_thumb_path), thumb_destination) do
          source_upload_path = Map.get(metadata, :source_upload_path)
          if is_binary(source_upload_path), do: File.rm(source_upload_path)

          {:ok,
           Map.merge(drop_prepared_paths(metadata), %{
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

  def cleanup_prepared(metadata) when is_map(metadata) do
    metadata
    |> prepared_paths()
    |> Enum.each(fn path ->
      if is_binary(path) do
        _ = File.rm(path)
      end
    end)

    :ok
  end

  def cleanup_prepared(_metadata), do: :ok

  @spec regenerate_thumbnail(String.t(), String.t(), map(), map(), boolean()) ::
          :ok | {:error, atom()}
  def regenerate_thumbnail(source_path, destination_path, config, metadata, op?)
      when is_binary(source_path) and is_binary(destination_path) do
    destination_path
    |> Path.dirname()
    |> File.mkdir_p!()

    generate_thumbnail(source_path, destination_path, config, metadata, op?)
  end

  @spec board_root() :: String.t()
  def board_root do
    Application.fetch_env!(:eirinchan, :build_output_root)
  end

  def image?(%{file_type: file_type, ext: ext}) when is_binary(file_type),
    do: String.starts_with?(file_type, "image/") and image_extension?(ext)

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
      ext == ".bmp" -> file_type in ["image/bmp", "image/x-ms-bmp"]
      ext == ".webp" -> file_type == "image/webp"
      ext == ".svg" -> file_type == "image/svg+xml"
      ext == ".jxl" -> file_type == "image/jxl"
      ext == ".webm" -> file_type == "video/webm"
      ext == ".mp4" -> file_type in ["video/mp4", "application/mp4"]
      ext == ".txt" -> file_type == "inode/x-empty" or String.starts_with?(file_type, "text/")
      true -> true
    end
  end

  def compatible_with_extension?(_ext, _file_type), do: false

  def ie_mime_type_exploit?(metadata, config) when is_map(metadata) do
    regex = Map.get(config, :ie_mime_type_detection)

    cond do
      regex in [false, nil, ""] ->
        false

      not image_extension?(Map.get(metadata, :ext)) ->
        false

      true ->
        metadata
        |> Map.get(:binary, "")
        |> binary_prefix(255)
        |> then(fn prefix ->
          case compile_config_regex(regex) do
            {:ok, compiled} -> Regex.match?(compiled, prefix)
            :error -> false
          end
        end)
    end
  end

  def ie_mime_type_exploit?(_metadata, _config), do: false

  def image_extension?(ext) when is_binary(ext), do: ext in @image_extensions
  def image_extension?(_ext), do: false

  def video_extension?(ext) when is_binary(ext), do: ext in @video_extensions
  def video_extension?(_ext), do: false

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

  defp maybe_media_metadata(path, file_type, ext, config) do
    cond do
      image?(%{file_type: file_type, ext: ext}) ->
        case image_metadata(path) do
          {:ok, data} -> data
          {:error, :invalid_image} -> %{width: nil, height: nil}
        end

      video_extension?(ext) ->
        case video_metadata(path, ext, config) do
          {:ok, data} -> data
          {:error, _reason} -> %{width: nil, height: nil}
        end

      true ->
        %{width: nil, height: nil}
    end
  end

  defp describe_without_normalizing(%Plug.Upload{} = upload, normalized_name, config) do
    with {:ok, digest} <- file_digest_metadata(upload.path) do
      ext = normalized_name |> Path.extname() |> String.downcase()
      file_type = detect_mime_type(upload.path, normalized_name)
      normalized_ext = normalized_media_extension(ext, file_type)
      media_metadata = maybe_media_metadata(upload.path, file_type, normalized_ext, config)

      {:ok,
       %{
         binary: digest.prefix,
         ext: normalized_ext,
         file_name: normalized_filename(normalized_name, config),
         file_size: digest.size,
         file_type: file_type,
         file_md5: digest.md5,
         image_width: media_metadata.width,
         image_height: media_metadata.height,
         spoiler: false
       }}
    else
      {:error, _reason} -> {:error, :upload_failed}
    end
  end

  defp binary_prefix(value, count) when is_binary(value) and is_integer(count) and count >= 0 do
    max = min(byte_size(value), count)
    binary_part(value, 0, max)
  end

  defp binary_prefix(_value, _count), do: ""

  defp compile_config_regex(%Regex{} = regex), do: {:ok, regex}

  defp compile_config_regex(pattern) when is_binary(pattern) do
    case Regex.run(~r{\A/(.*)/([a-z]*)\z}s, pattern, capture: :all_but_first) do
      [source, modifiers] ->
        Regex.compile(source, regex_options(modifiers))

      _ ->
        :error
    end
  end

  defp compile_config_regex(_pattern), do: :error

  defp regex_options(modifiers) do
    modifiers
    |> String.graphemes()
    |> Enum.reduce("", fn
      "i", acc -> acc <> "i"
      "m", acc -> acc <> "m"
      "s", acc -> acc <> "s"
      "u", acc -> acc <> "u"
      _, acc -> acc
    end)
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

    thumb_ext =
      thumbnail_extension(
        %{
          ext: ext,
          file_type: ext |> MIME.type() |> to_string()
        },
        config
      )

    thumb_path = Path.join([board_root(), board.uri, config.dir.thumb, "#{base}s#{thumb_ext}"])

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
      normalized in ["localhost", "localhost.localdomain"] ->
        false

      String.ends_with?(normalized, ".localhost") ->
        false

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

  defp normalize_stored_upload(path, config, metadata) do
    if image?(metadata) do
      args =
        []
        |> maybe_add_auto_orient(config)
        |> maybe_add_strip_exif(config)
        |> Kernel.++([path])

      case args do
        [^path] ->
          :ok

        _ ->
          case System.cmd("mogrify", args, stderr_to_stdout: true) do
            {_output, 0} -> :ok
            _ -> {:error, :upload_failed}
          end
      end
    else
      :ok
    end
  end

  defp create_staged_upload_path(ext) do
    path =
      Path.join(staging_root(), "upload-#{System.unique_integer([:positive])}#{ext}")

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    {:ok, path}
  end

  defp create_staged_thumbnail_path(ext) do
    path =
      Path.join(staging_root(), "thumb-#{System.unique_integer([:positive])}#{ext}")

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    {:ok, path}
  end

  defp staging_root do
    Path.join(System.tmp_dir!(), "eirinchan-upload-staging")
  end

  defp maybe_add_auto_orient(args, config) do
    if Map.get(config, :convert_auto_orient, true), do: args ++ ["-auto-orient"], else: args
  end

  defp maybe_add_strip_exif(args, config) do
    if Map.get(config, :strip_exif, true), do: args ++ ["-strip"], else: args
  end

  defp normalized_upload_metadata(path, metadata, config) do
    if image?(metadata) do
      temp_path = "#{path}.normalized"

      with :ok <- File.cp(path, temp_path),
           :ok <- normalize_stored_upload(temp_path, config, metadata),
           {:ok, normalized} <- refresh_stored_metadata(temp_path, metadata, config) do
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

  defp prepared_paths(metadata) do
    [
      Map.get(metadata, :staged_path),
      Map.get(metadata, :staged_thumb_path)
    ]
  end

  defp drop_prepared_paths(metadata) do
    metadata
    |> Map.delete(:prepared_upload)
    |> Map.delete(:staged_path)
    |> Map.delete(:staged_thumb_path)
    |> Map.delete(:source_upload_path)
  end

  defp refresh_stored_metadata(path, metadata, config) do
    with {:ok, digest} <- file_digest_metadata(path) do
      file_type = detect_mime_type(path, metadata.file_name)
      normalized_ext = normalized_media_extension(metadata.ext, file_type)
      media_metadata = maybe_media_metadata(path, file_type, normalized_ext, config)

      {:ok,
       metadata
       |> Map.put(:binary, digest.prefix)
       |> Map.put(:ext, normalized_ext)
       |> Map.put(:file_size, digest.size)
       |> Map.put(:file_type, file_type)
       |> Map.put(:file_md5, digest.md5)
       |> Map.put(:image_width, media_metadata.width)
       |> Map.put(:image_height, media_metadata.height)}
    else
      {:error, _reason} -> {:error, :upload_failed}
    end
  end

  defp file_digest_metadata(path) do
    max_prefix = 255

    digest =
      path
      |> File.stream!([], 64 * 1024)
      |> Enum.reduce(%{hash: :crypto.hash_init(:md5), size: 0, prefix: []}, fn chunk, acc ->
        prefix =
          if IO.iodata_length(acc.prefix) >= max_prefix do
            acc.prefix
          else
            remaining = max_prefix - IO.iodata_length(acc.prefix)
            [acc.prefix | binary_part(chunk, 0, min(byte_size(chunk), remaining))]
          end

        %{
          hash: :crypto.hash_update(acc.hash, chunk),
          size: acc.size + byte_size(chunk),
          prefix: prefix
        }
      end)

    {:ok,
     %{
       size: digest.size,
       md5: digest.hash |> :crypto.hash_final() |> Base.encode64(),
       prefix: IO.iodata_to_binary(digest.prefix)
     }}
  rescue
    _error ->
      {:error, :upload_failed}
  end

  defp image_metadata(path) do
    case System.cmd("identify", ["-format", "%w %h", first_frame_path(path)],
           stderr_to_stdout: true
         ) do
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
      image?(metadata) ->
        with :ok <- generate_image_thumbnail(source, destination, config, op?),
             :ok <- maybe_compress_jpeg_thumbnail(destination) do
          if Map.get(metadata, :spoiler),
            do: generate_spoiler_thumbnail(destination, config),
            else: :ok
        end

      video_extension?(metadata.ext) and get_in(config, [:webm, :use_ffmpeg]) ->
        with :ok <- generate_video_thumbnail(source, destination, config, metadata, op?),
             :ok <- maybe_compress_jpeg_thumbnail(destination) do
          if Map.get(metadata, :spoiler),
            do: generate_spoiler_thumbnail(destination, config),
            else: :ok
        end

      true ->
        generate_placeholder_thumbnail(destination, config, metadata)
    end
  end

  defp generate_image_thumbnail(source, destination, config, op?) do
    cond do
      animated_gif_thumb?(source, config) ->
        generate_animated_gif_thumbnail(source, destination, config, op?)

      minimum_copy_resize?(source, config) ->
        case File.cp(source, destination) do
          :ok -> :ok
          {:error, _reason} -> {:error, :upload_failed}
        end

      true ->
        geometry = image_thumbnail_geometry(config, op?)

        case System.cmd(
               "convert",
               image_thumbnail_args(source, destination, geometry, config),
               stderr_to_stdout: true
             ) do
          {_output, 0} -> :ok
          _ -> {:error, :upload_failed}
        end
    end
  end

  defp generate_animated_gif_thumbnail(source, destination, config, op?) do
    geometry = image_thumbnail_geometry(config, op?)
    frames = max(Map.get(config, :thumb_keep_animation_frames, 1) - 1, 0)
    source_frames = "#{source}[0-#{frames}]"

    case System.cmd(
           "convert",
           [
             source_frames,
             "-coalesce",
             "-thumbnail",
             geometry,
             "-layers",
             "Optimize",
             destination
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      _ -> {:error, :upload_failed}
    end
  end

  defp first_frame_path(path) when is_binary(path) do
    case String.downcase(Path.extname(path)) do
      ext when ext in [".gif", ".webp"] -> path <> "[0]"
      _ -> path
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

  defp animated_gif_thumb?(source, config) do
    String.downcase(Path.extname(source)) == ".gif" and
      gif_thumbnail_extension(config) == ".gif" and
      max(Map.get(config, :thumb_keep_animation_frames, 1), 1) > 1
  end

  defp image_thumbnail_args(source, destination, geometry, config) do
    []
    |> Kernel.++([first_frame_path(source)])
    |> maybe_add_thumbnail_auto_orient(config)
    |> Kernel.++(["-thumbnail", geometry, destination])
  end

  defp maybe_add_thumbnail_auto_orient(args, config) do
    if Map.get(config, :convert_auto_orient, true), do: args ++ ["-auto-orient"], else: args
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

      is_binary(icon_name) ->
        resolve_bundled_icon(icon_name)

      true ->
        nil
    end
  end

  defp resolve_bundled_icon(icon_name) do
    candidates = [
      Path.join(Application.app_dir(:eirinchan, "priv/static/static"), icon_name),
      Path.join(Application.app_dir(:eirinchan, "priv/static"), icon_name)
    ]

    Enum.find(candidates, &File.exists?/1)
  end

  defp generate_spoiler_thumbnail(destination, _config) do
    temp_destination = destination <> ".blur.png"

    case System.cmd(
           "convert",
           [destination, "-blur", "0x8", temp_destination],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        case File.rename(temp_destination, destination) do
          :ok ->
            :ok

          {:error, _reason} ->
            _ = File.rm(temp_destination)
            {:error, :upload_failed}
        end

      _ ->
        _ = File.rm(temp_destination)
        {:error, :upload_failed}
    end
  end

  defp maybe_compress_jpeg_thumbnail(destination) do
    case String.downcase(Path.extname(destination)) do
      ext when ext in [".jpg", ".jpeg"] ->
        case System.cmd(
               "mogrify",
               ["-strip", "-quality", Integer.to_string(@jpeg_thumbnail_quality), destination],
               stderr_to_stdout: true
             ) do
          {_output, 0} -> :ok
          _ -> {:error, :upload_failed}
        end

      _ ->
        :ok
    end
  end

  defp thumbnail_extension(metadata, config) do
    cond do
      video_extension?(metadata.ext) ->
        ".jpg"

      metadata.ext in [".jpg", ".jpeg"] ->
        ".jpg"

      metadata.ext == ".png" ->
        ".png"

      metadata.ext == ".gif" ->
        gif_thumbnail_extension(config)

      true ->
        ".png"
    end
  end

  defp gif_thumbnail_extension(config) do
    case Map.get(config, :thumb_ext, "") do
      "" -> ".gif"
      "gif" -> ".gif"
      ".gif" -> ".gif"
      "jpg" -> ".jpg"
      ".jpg" -> ".jpg"
      "jpeg" -> ".jpg"
      ".jpeg" -> ".jpg"
      "png" -> ".png"
      ".png" -> ".png"
      _ -> ".png"
    end
  end

  defp video_metadata(path, ext, config) do
    ffprobe = get_in(config, [:webm, :ffprobe_path]) || "ffprobe"

    case System.cmd(
           ffprobe,
           ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", path],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        with {:ok, data} <- Jason.decode(output),
             :ok <- validate_video_metadata(data, ext, config),
             %{"width" => width, "height" => height} = stream <- primary_video_stream(data) do
          {:ok, %{width: width, height: height, duration: video_duration(data), stream: stream}}
        else
          _ -> {:error, :invalid_video}
        end

      _ ->
        {:error, :invalid_video}
    end
  end

  defp primary_video_stream(%{"streams" => streams}) when is_list(streams) do
    Enum.find(streams, fn stream -> Map.get(stream, "codec_type") == "video" end)
  end

  defp primary_video_stream(_), do: nil

  defp audio_streams(%{"streams" => streams}) when is_list(streams) do
    Enum.filter(streams, fn stream -> Map.get(stream, "codec_type") == "audio" end)
  end

  defp audio_streams(_), do: []

  defp video_duration(%{"format" => %{"duration" => duration}}) when is_binary(duration) do
    case Float.parse(duration) do
      {value, _} -> value
      :error -> 0.0
    end
  end

  defp video_duration(_), do: 0.0

  defp validate_video_metadata(data, ext, config) do
    with %{"format" => format} <- data,
         %{"format_name" => format_name} <- format,
         %{"codec_name" => codec} <- primary_video_stream(data),
         :ok <- validate_video_format(ext, format_name, codec),
         :ok <- validate_video_audio(data, config),
         :ok <- validate_video_duration(data, config) do
      :ok
    else
      _ -> {:error, :invalid_video}
    end
  end

  defp validate_video_format(".webm", "matroska,webm", codec) when codec in ["vp8", "vp9", "av1"],
    do: :ok

  defp validate_video_format(".webm", _format_name, _codec), do: {:error, :invalid_video}

  defp validate_video_format(".mp4", format_name, codec) do
    if String.contains?(format_name, "mp4") and codec in ["h264", "av1"] do
      :ok
    else
      {:error, :invalid_video}
    end
  end

  defp validate_video_format(_ext, _format_name, _codec), do: {:error, :invalid_video}

  defp validate_video_audio(data, config) do
    if get_in(config, [:webm, :allow_audio]) || audio_streams(data) == [] do
      :ok
    else
      {:error, :invalid_video}
    end
  end

  defp validate_video_duration(data, config) do
    max_length = get_in(config, [:webm, :max_length]) || 120

    if video_duration(data) <= max_length do
      :ok
    else
      {:error, :invalid_video}
    end
  end

  defp generate_video_thumbnail(source, destination, config, metadata, op?) do
    ffmpeg = get_in(config, [:webm, :ffmpeg_path]) || "ffmpeg"
    {width, height} = thumbnail_dimensions_for_video(metadata, config, op?)
    midpoint = max(floor(Map.get(metadata, :duration, 0.0) / 2), 0)

    args = [
      "-y",
      "-strict",
      "-2",
      "-ss",
      Integer.to_string(midpoint),
      "-i",
      source,
      "-v",
      "quiet",
      "-an",
      "-vframes",
      "1",
      "-f",
      "mjpeg",
      "-vf",
      "scale=#{width}:#{height}",
      destination
    ]

    case System.cmd(ffmpeg, args, stderr_to_stdout: true) do
      {_output, 0} ->
        if File.exists?(destination),
          do: :ok,
          else: generate_video_thumbnail_from_start(source, destination, config, metadata, op?)

      _ ->
        generate_video_thumbnail_from_start(source, destination, config, metadata, op?)
    end
  end

  defp generate_video_thumbnail_from_start(source, destination, config, metadata, op?) do
    ffmpeg = get_in(config, [:webm, :ffmpeg_path]) || "ffmpeg"
    {width, height} = thumbnail_dimensions_for_video(metadata, config, op?)

    case System.cmd(
           ffmpeg,
           [
             "-y",
             "-strict",
             "-2",
             "-ss",
             "0",
             "-i",
             source,
             "-v",
             "quiet",
             "-an",
             "-vframes",
             "1",
             "-f",
             "mjpeg",
             "-vf",
             "scale=#{width}:#{height}",
             destination
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        if File.exists?(destination), do: :ok, else: {:error, :upload_failed}

      _ ->
        {:error, :upload_failed}
    end
  end

  defp thumbnail_dimensions_for_video(metadata, config, op?) do
    max_width = if op?, do: config.thumb_op_width, else: config.thumb_width
    max_height = if op?, do: config.thumb_op_height, else: config.thumb_height

    case fit_dimensions(
           media_dimension(metadata, :image_width, :width),
           media_dimension(metadata, :image_height, :height),
           max_width,
           max_height
         ) do
      {width, height} -> {width, height}
      nil -> {max_width, max_height}
    end
  end

  defp media_dimension(metadata, primary_key, fallback_key) when is_map(metadata) do
    Map.get(metadata, primary_key) ||
      Map.get(metadata, fallback_key) ||
      Map.get(metadata, Atom.to_string(primary_key)) ||
      Map.get(metadata, Atom.to_string(fallback_key))
  end

  defp media_dimension(_metadata, _primary_key, _fallback_key), do: nil

  defp fit_dimensions(nil, _height, _max_width, _max_height), do: nil
  defp fit_dimensions(_width, nil, _max_width, _max_height), do: nil

  defp fit_dimensions(width, height, max_width, max_height)
       when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    scale = min(max_width / width, max_height / height)
    scale = if scale > 1.0, do: 1.0, else: scale
    {max(trunc(width * scale), 1), max(trunc(height * scale), 1)}
  end

  defp normalized_media_extension(ext, file_type) when is_binary(ext) and is_binary(file_type) do
    case canonical_extension_for_file_type(file_type) do
      canonical when canonical in @image_extensions and ext in @image_extensions -> canonical
      _ -> ext
    end
  end

  defp normalized_media_extension(ext, _file_type), do: ext

  defp canonical_extension_for_file_type("image/jpeg"), do: ".jpg"
  defp canonical_extension_for_file_type("image/png"), do: ".png"
  defp canonical_extension_for_file_type("image/gif"), do: ".gif"
  defp canonical_extension_for_file_type("image/bmp"), do: ".bmp"
  defp canonical_extension_for_file_type("image/x-ms-bmp"), do: ".bmp"
  defp canonical_extension_for_file_type("image/webp"), do: ".webp"
  defp canonical_extension_for_file_type(_file_type), do: nil

  defp normalized_filename(filename, _config) do
    original_ext = Path.extname(filename)

    ext =
      filename
      |> Path.extname()
      |> String.downcase()

    max_length = 256

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
