defmodule Eirinchan.Posts.Validation do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.AccessList
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Uploads

  def validate_body(op?, attrs, config) do
    require_body = if(op?, do: config.force_body_op, else: config.force_body)

    has_media =
      present_embed?(attrs) or
        match?(%Plug.Upload{}, Map.get(attrs, "file")) or
        Map.get(attrs, "__upload_entries__", []) != []

    if (require_body or not has_media) and body_blank?(attrs["body"]) do
      {:error, :body_required}
    else
      :ok
    end
  end

  def validate_body_limits(attrs, config) do
    body = attrs["body"] || ""

    cond do
      is_integer(config.max_body) and config.max_body > 0 and
          String.length(body) > config.max_body ->
        {:error, :body_too_long}

      is_integer(config.maximum_lines) and config.maximum_lines > 0 and
          String.split(body, "\n") |> length() > config.maximum_lines ->
        {:error, :too_many_lines}

      true ->
        :ok
    end
  end

  def validate_upload(op?, attrs, config, request) do
    entries = Map.get(attrs, "__upload_entries__", [])
    embed? = present_embed?(attrs)

    cond do
      op? and config.force_image_op and entries == [] and not embed? ->
        {:error, :file_required}

      op? and length(entries) > 1 and AccessList.enabled?() and
          not AccessList.allowed?(request[:remote_ip] || request["remote_ip"]) ->
        {:error, :access_list}

      entries == [] ->
        :ok

      true ->
        with :ok <-
               Enum.reduce_while(entries, :ok, fn %{upload: upload, metadata: metadata}, :ok ->
                 case validate_upload_entry(upload, metadata, config, op?) do
                   :ok -> {:cont, :ok}
                   error -> {:halt, error}
                 end
               end),
             :ok <- validate_total_upload_size(entries, config) do
          :ok
        end
    end
  end

  def validate_image_dimensions(attrs, _config)
      when not is_map_key(attrs, "__upload_entries__"),
      do: :ok

  def validate_image_dimensions(attrs, config) do
    attrs
    |> Map.get("__upload_entries__", [])
    |> Enum.reduce_while(:ok, fn %{metadata: metadata}, :ok ->
      case validate_image_entry_dimensions(metadata, config) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def validate_reply_limit(_board, nil, _config, _repo), do: :ok

  def validate_reply_limit(board, thread, config, repo) do
    if config.reply_hard_limit in [0, nil] do
      :ok
    else
      replies =
        repo.aggregate(
          from(post in Post, where: post.board_id == ^board.id and post.thread_id == ^thread.id),
          :count,
          :id
        )

      if replies >= config.reply_hard_limit, do: {:error, :reply_hard_limit}, else: :ok
    end
  end

  def validate_image_limit(_board, nil, _attrs, _config, _repo), do: :ok

  def validate_image_limit(_board, _thread, attrs, _config, _repo)
      when not is_map_key(attrs, "__upload_entries__"),
      do: :ok

  def validate_image_limit(_board, _thread, %{"__upload_entries__" => []}, _config, _repo),
    do: :ok

  def validate_image_limit(board, thread, attrs, config, repo) do
    if config.image_hard_limit in [0, nil] do
      :ok
    else
      additional_images =
        attrs
        |> Map.get("__upload_entries__", [])
        |> Enum.count(fn %{metadata: metadata} -> Uploads.image?(metadata) end)

      images =
        repo.aggregate(
          from(
            post in Post,
            where:
              post.board_id == ^board.id and
                (post.id == ^thread.id or post.thread_id == ^thread.id) and
                like(post.file_type, "image/%")
          ),
          :count,
          :id
        )

      extra_images =
        repo.aggregate(
          from(
            post_file in PostFile,
            join: post in Post,
            on: post_file.post_id == post.id,
            where:
              post.board_id == ^board.id and
                (post.id == ^thread.id or post.thread_id == ^thread.id) and
                like(post_file.file_type, "image/%")
          ),
          :count,
          :id
        )

      if images + extra_images + additional_images > config.image_hard_limit,
        do: {:error, :image_hard_limit},
        else: :ok
    end
  end

  def validate_duplicate_upload(_board, _thread, attrs, _config, _repo)
      when not is_map_key(attrs, "__upload_entries__"),
      do: :ok

  def validate_duplicate_upload(_board, thread, attrs, config, repo) do
    md5s =
      attrs
      |> Map.get("__upload_entries__", [])
      |> Enum.map(fn %{metadata: metadata} -> metadata.file_md5 end)

    if Enum.uniq(md5s) != md5s do
      {:error, :duplicate_file}
    else
      Enum.reduce_while(md5s, :ok, fn md5, :ok ->
        case config.duplicate_file_mode do
          "global" ->
            duplicate? =
              repo.exists?(
                from post in Post, where: post.file_md5 == ^md5 and not is_nil(post.file_md5)
              ) or
                repo.exists?(
                  from post_file in PostFile,
                    where: post_file.file_md5 == ^md5 and not is_nil(post_file.file_md5)
                )

            if duplicate?, do: {:halt, {:error, :duplicate_file}}, else: {:cont, :ok}

          "thread" when not is_nil(thread) ->
            duplicate? =
              repo.exists?(
                from post in Post,
                  where:
                    (post.id == ^thread.id or post.thread_id == ^thread.id) and
                      post.file_md5 == ^md5 and not is_nil(post.file_md5)
              ) or
                repo.exists?(
                  from post_file in PostFile,
                    join: post in Post,
                    on: post_file.post_id == post.id,
                    where:
                      (post.id == ^thread.id or post.thread_id == ^thread.id) and
                        post_file.file_md5 == ^md5 and not is_nil(post_file.file_md5)
                )

            if duplicate?, do: {:halt, {:error, :duplicate_file}}, else: {:cont, :ok}

          _ ->
            {:cont, :ok}
        end
      end)
    end
  end

  defp present_embed?(attrs) when is_map(attrs) do
    case Map.get(attrs, "embed") do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end

  defp validate_upload_entry(upload, metadata, config, op?) do
    with :ok <- validate_upload_type(upload, metadata, config, op?),
         :ok <- validate_upload_content(metadata),
         :ok <- validate_upload_size(metadata, config) do
      :ok
    end
  end

  defp validate_upload_type(%Plug.Upload{} = upload, nil, config, op?),
    do:
      validate_upload_type(
        upload,
        %{ext: upload.filename |> Path.extname() |> String.downcase()},
        config,
        op?
      )

  defp validate_upload_type(_upload, %{ext: ext}, config, op?) do
    allowed =
      if op? and is_list(config.allowed_ext_files_op) do
        config.allowed_ext_files_op
      else
        config.allowed_ext_files
      end
      |> Kernel.||([])
      |> Enum.map(&String.downcase/1)

    if ext in allowed do
      :ok
    else
      {:error, :invalid_file_type}
    end
  end

  defp validate_upload_size(nil, _config), do: {:error, :upload_failed}

  defp validate_upload_size(upload_metadata, config) do
    max_filesize = config.max_filesize

    if is_integer(max_filesize) and max_filesize > 0 and upload_metadata.file_size > max_filesize do
      {:error, :file_too_large}
    else
      :ok
    end
  end

  defp validate_total_upload_size(entries, config) when is_list(entries) do
    max_filesize = config.max_filesize

    cond do
      not (is_integer(max_filesize) and max_filesize > 0) ->
        :ok

      entries == [] ->
        :ok

      config.multiimage_method == "split" ->
        total_size =
          Enum.reduce(entries, 0, fn %{metadata: metadata}, acc ->
            acc + (metadata.file_size || 0)
          end)

        if total_size > max_filesize, do: {:error, :file_too_large}, else: :ok

      true ->
        :ok
    end
  end

  defp validate_upload_content(nil), do: {:error, :upload_failed}

  defp validate_upload_content(metadata) do
    if Uploads.compatible_with_extension?(metadata) do
      :ok
    else
      if Uploads.image_extension?(metadata.ext) do
        {:error, :invalid_image}
      else
        {:error, :invalid_file_type}
      end
    end
  end

  defp validate_image_entry_dimensions(metadata, config) do
    width = metadata.image_width || 0
    height = metadata.image_height || 0

    cond do
      not Uploads.image?(metadata) ->
        :ok

      width < 1 or height < 1 ->
        {:error, :invalid_image}

      config.max_image_width not in [0, nil] and width > config.max_image_width ->
        {:error, :image_too_large}

      config.max_image_height not in [0, nil] and height > config.max_image_height ->
        {:error, :image_too_large}

      true ->
        :ok
    end
  end

  defp body_blank?(nil), do: true

  defp body_blank?(value) when is_binary(value) do
    value
    |> String.replace(~r/\s/u, "")
    |> Kernel.==("")
  end
end
