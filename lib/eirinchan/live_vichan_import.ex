defmodule Eirinchan.LiveVichanImport do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Build
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias Eirinchan.Uploads

  @script Path.expand("../../priv/scripts/export_live_vichan_page.php", __DIR__)

  def import_page(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    source_root = Keyword.get(opts, :source_root, "/path/to/vichan")
    board_uri = Keyword.get(opts, :board, "bant")
    limit = Keyword.get(opts, :limit, 10)

    with {:ok, payload} <- export_live_page(source_root, board_uri, limit),
         {:ok, board} <- ensure_board(payload["board"], repo),
         {:ok, result} <- import_payload(board, payload, repo, source_root),
         :ok <- shuffle_all_threads(repo),
         :ok <- rebuild_all_boards(repo) do
      {:ok, Map.merge(result, %{board: board.uri, build_root: Build.board_root()})}
    end
  end

  defp export_live_page(source_root, board_uri, limit) do
    case System.cmd("php", [@script, source_root, board_uri, Integer.to_string(limit)],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        {:ok, Jason.decode!(output)}

      {output, code} ->
        {:error, {:live_export_failed, code, output}}
    end
  end

  defp ensure_board(%{"uri" => uri, "title" => title} = attrs, repo) do
    case Boards.get_board_by_uri(uri, repo: repo) do
      %BoardRecord{} = board ->
        {:ok, board}

      nil ->
        Boards.create_board(
          %{
            "uri" => uri,
            "title" => title,
            "subtitle" => Map.get(attrs, "subtitle")
          },
          repo: repo
        )
    end
  end

  defp import_payload(%BoardRecord{} = board, payload, repo, source_root) do
    instance_config = Settings.current_instance_config()
    runtime_board = Boards.BoardRecord.to_board(board)

    config =
      Config.compose(nil, instance_config, board.config_overrides || %{}, board: runtime_board)

    grouped =
      payload["posts"]
      |> Enum.group_by(fn row -> row["thread"] || row["id"] end)

    imported =
      payload["thread_ids"]
      |> Enum.map(fn legacy_thread_id ->
        import_thread(
          board,
          grouped[legacy_thread_id] || [],
          repo,
          config,
          source_root,
          legacy_thread_id
        )
      end)

    case Enum.find(imported, &match?({:error, _}, &1)) do
      nil ->
        merged =
          Enum.reduce(imported, %{threads: 0, replies: 0, files: 0, post_map: %{}}, fn {:ok, row},
                                                                                       acc ->
            %{
              threads: acc.threads + row.threads,
              replies: acc.replies + row.replies,
              files: acc.files + row.files,
              post_map: Map.merge(acc.post_map, row.post_map)
            }
          end)

        :ok = rewrite_imported_citations(board, grouped, merged.post_map, repo)
        {:ok, Map.drop(merged, [:post_map])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_thread(
         %BoardRecord{} = board,
         [op | replies],
         repo,
         config,
         source_root,
         legacy_thread_id
       ) do
    case existing_thread_map(board, [op | replies], repo, legacy_thread_id) do
      {:ok, post_map} ->
        {:ok, %{threads: 0, replies: 0, files: 0, post_map: post_map}}

      :error ->
        repo.transaction(
          fn ->
            inserted_op = insert_post(board, nil, op, repo, config, source_root)

            {post_map, reply_count, file_count} =
              Enum.reduce(
                replies,
                {%{legacy_thread_id => inserted_op.id, op["id"] => inserted_op.id}, 0,
                 count_files(op)},
                fn reply, {map, count, files} ->
                  inserted_reply =
                    insert_post(board, inserted_op, reply, repo, config, source_root)

                  {Map.put(map, reply["id"], inserted_reply.id), count + 1,
                   files + count_files(reply)}
                end
              )

            %{
              threads: 1,
              replies: reply_count,
              files: file_count,
              post_map: post_map
            }
          end,
          timeout: :infinity
        )
        |> case do
          {:ok, summary} -> {:ok, summary}
          {:error, reason} -> {:error, reason}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp existing_thread_map(%BoardRecord{} = board, [op | replies], repo, legacy_thread_id) do
    inserted_at = DateTime.from_unix!(op["time"]) |> DateTime.truncate(:second)
    op_slug = blank_to_nil(op["slug"])
    {op_body, _codes, _alts} = extract_body_and_flags(op["body_nomarkup"] || op["body"] || "")

    query =
      from post in Post,
        where:
          post.board_id == ^board.id and is_nil(post.thread_id) and
            post.inserted_at == ^inserted_at

    query =
      if op_slug do
        from post in query, where: post.slug == ^op_slug
      else
        from post in query, where: post.body == ^op_body
      end

    case repo.one(query) do
      %Post{} = existing_op ->
        existing_replies =
          repo.all(
            from post in Post,
              where: post.thread_id == ^existing_op.id,
              order_by: [asc: post.inserted_at, asc: post.id]
          )

        if length(existing_replies) == length(replies) do
          reply_map =
            Enum.zip(replies, existing_replies)
            |> Enum.into(%{}, fn {legacy_reply, existing_reply} ->
              {legacy_reply["id"], existing_reply.id}
            end)

          {:ok,
           Map.merge(%{legacy_thread_id => existing_op.id, op["id"] => existing_op.id}, reply_map)}
        else
          :error
        end

      nil ->
        :error
    end
  end

  defp insert_post(%BoardRecord{} = board, thread, legacy_row, repo, config, source_root) do
    {body, flag_codes, flag_alts} =
      extract_body_and_flags(legacy_row["body_nomarkup"] || legacy_row["body"] || "")

    inserted_at = DateTime.from_unix!(legacy_row["time"]) |> DateTime.truncate(:second)
    bump_at = legacy_bump_at(legacy_row)

    primary_file =
      legacy_row["files"]
      |> List.wrap()
      |> Enum.reject(&blank_file?/1)
      |> Enum.at(0)

    extra_files =
      legacy_row["files"]
      |> List.wrap()
      |> Enum.reject(&blank_file?/1)
      |> Enum.drop(1)

    primary_attrs =
      case primary_file do
        nil -> %{}
        file -> copy_asset_and_build_attrs(board, file, config, source_root, is_nil(thread))
      end

    post =
      %Post{
        board_id: board.id,
        thread_id: thread && thread.id,
        name: blank_to_nil(legacy_row["name"]),
        email: blank_to_nil(legacy_row["email"]),
        subject: blank_to_nil(legacy_row["subject"]),
        password: blank_to_nil(legacy_row["password"]),
        body: body,
        embed: blank_to_nil(legacy_row["embed"]),
        flag_codes: flag_codes,
        flag_alts: flag_alts,
        tripcode: blank_to_nil(legacy_row["trip"]),
        file_name: primary_attrs[:file_name],
        file_path: primary_attrs[:file_path],
        thumb_path: primary_attrs[:thumb_path],
        file_size: primary_attrs[:file_size],
        file_type: primary_attrs[:file_type],
        file_md5: primary_attrs[:file_md5],
        image_width: primary_attrs[:image_width],
        image_height: primary_attrs[:image_height],
        spoiler: primary_attrs[:spoiler] || false,
        bump_at: if(is_nil(thread), do: bump_at, else: nil),
        sticky: truthy?(legacy_row["sticky"]),
        locked: truthy?(legacy_row["locked"]),
        cycle: truthy?(legacy_row["cycle"]),
        sage: truthy?(legacy_row["sage"]),
        slug: blank_to_nil(legacy_row["slug"]),
        ip_subnet: nil,
        inserted_at: inserted_at,
        updated_at: inserted_at
      }
      |> repo.insert!()

    Enum.with_index(extra_files, 1)
    |> Enum.each(fn {file, position} ->
      attrs =
        copy_asset_and_build_attrs(
          board,
          file,
          config,
          source_root,
          is_nil(thread),
          Integer.to_string(position)
        )

      %PostFile{
        post_id: post.id,
        position: position,
        file_name: attrs[:file_name],
        file_path: attrs[:file_path],
        thumb_path: attrs[:thumb_path],
        file_size: attrs[:file_size],
        file_type: attrs[:file_type],
        file_md5: attrs[:file_md5],
        image_width: attrs[:image_width],
        image_height: attrs[:image_height],
        spoiler: attrs[:spoiler] || false,
        inserted_at: inserted_at,
        updated_at: inserted_at
      }
      |> repo.insert!()
    end)

    post
  end

  defp copy_asset_and_build_attrs(
         %BoardRecord{} = board,
         legacy_file,
         config,
         source_root,
         op?,
         _suffix \\ nil
       ) do
    if deleted_legacy_file?(legacy_file) do
      %{
        file_name: legacy_file["filename"] || legacy_file["name"] || "deleted",
        file_path: "deleted",
        thumb_path: nil,
        file_size: integer_or_nil(legacy_file["size"]),
        file_type:
          legacy_file["type"] || MIME.from_path(legacy_file["filename"] || "") ||
            "application/octet-stream",
        file_md5: legacy_file["hash"] || "deleted",
        image_width: integer_or_nil(legacy_file["width"]),
        image_height: integer_or_nil(legacy_file["height"]),
        spoiler: truthy?(legacy_file["spoiler"])
      }
    else
      source_rel = file_source_rel(board, legacy_file)
      source_abs = Path.join(source_root, source_rel)

      unless File.exists?(source_abs) do
        raise "missing source asset: #{source_abs}"
      end

      stored_name =
        legacy_file["file"] ||
          Path.basename(
            legacy_file["file_path"] || legacy_file["full_path"] || legacy_file["filename"]
          )

      spoiler? = truthy?(legacy_file["spoiler"]) or spoiler_thumb?(legacy_file)

      thumb_name =
        if spoiler_thumb?(legacy_file) do
          Path.basename(stored_name)
        else
          legacy_file["thumb"] ||
          Path.basename(stored_name)
        end

      file_rel = "/#{board.uri}/src/#{stored_name}"
      thumb_rel = "/#{board.uri}/thumb/#{thumb_name}"
      file_abs = Uploads.filesystem_path(file_rel)
      thumb_abs = Uploads.filesystem_path(thumb_rel)

      file_abs |> Path.dirname() |> File.mkdir_p!()
      thumb_abs |> Path.dirname() |> File.mkdir_p!()
      File.cp!(source_abs, file_abs)

      metadata =
        media_metadata(file_abs, legacy_file)
        |> Map.put(:file_name, legacy_file["filename"] || legacy_file["name"] || stored_name)
        |> Map.put(:file_path, file_rel)
        |> Map.put(:thumb_path, thumb_rel)
        |> Map.put(:spoiler, spoiler?)

      :ok = Uploads.regenerate_thumbnail(file_abs, thumb_abs, config, metadata, op?)

      %{
        file_name: metadata.file_name,
        file_path: file_rel,
        thumb_path: thumb_rel,
        file_size: metadata.file_size,
        file_type: metadata.file_type,
        file_md5: metadata.file_md5,
        image_width: metadata.image_width,
        image_height: metadata.image_height,
        spoiler: metadata.spoiler
      }
    end
  end

  defp media_metadata(file_abs, legacy_file) do
    binary = File.read!(file_abs)
    ext = Path.extname(file_abs) |> String.downcase()

    %{
      ext: ext,
      file_size: byte_size(binary),
      file_type: legacy_file["type"] || MIME.from_path(file_abs) || "application/octet-stream",
      file_md5: :crypto.hash(:md5, binary) |> Base.encode64(),
      image_width: integer_or_nil(legacy_file["width"]),
      image_height: integer_or_nil(legacy_file["height"])
    }
  end

  defp file_source_rel(%BoardRecord{} = board, legacy_file) do
    cond do
      is_binary(legacy_file["file_path"]) and legacy_file["file_path"] != "" ->
        String.trim_leading(legacy_file["file_path"], "/")

      is_binary(legacy_file["file"]) and legacy_file["file"] != "" ->
        Path.join([board.uri, "src", legacy_file["file"]])

      is_binary(legacy_file["full_path"]) and legacy_file["full_path"] != "" ->
        Path.join([board.uri, "src", Path.basename(legacy_file["full_path"])])

      true ->
        raise "legacy file entry missing file path"
    end
  end

  defp rewrite_imported_citations(%BoardRecord{} = board, grouped, post_map, repo) do
    grouped
    |> Map.values()
    |> List.flatten()
    |> Enum.each(fn row ->
      new_post_id = Map.fetch!(post_map, row["id"])
      original_body = row["body_nomarkup"] || row["body"] || ""
      {clean_body, _codes, _alts} = extract_body_and_flags(original_body)
      rewritten = remap_cites(clean_body, post_map)

      repo.update_all(from(post in Post, where: post.id == ^new_post_id), set: [body: rewritten])

      extract_cited_ids(rewritten)
      |> Enum.uniq()
      |> Enum.each(fn target_id ->
        if repo.get_by(Post, id: target_id, board_id: board.id) do
          now = now_usec()

          repo.insert_all(
            "cites",
            [
              %{
                post_id: new_post_id,
                target_post_id: target_id,
                inserted_at: now,
                updated_at: now
              }
            ],
            on_conflict: :nothing
          )

          repo.insert_all(
            "nntp_references",
            [
              %{
                post_id: new_post_id,
                target_post_id: target_id,
                inserted_at: now,
                updated_at: now
              }
            ],
            on_conflict: :nothing
          )
        end
      end)
    end)

    :ok
  end

  defp remap_cites(body, post_map) when is_binary(body) do
    Regex.replace(~r/>>(\d+)/u, body, fn _, id ->
      case Map.get(post_map, String.to_integer(id)) do
        nil -> ">>#{id}"
        mapped -> ">>#{mapped}"
      end
    end)
  end

  defp extract_cited_ids(body) do
    Regex.scan(~r/>>(\d+)/u, body)
    |> Enum.map(fn [_, id] -> String.to_integer(id) end)
  end

  defp extract_body_and_flags(body) do
    flags = tag_values(body, "flag") |> split_modifier_values()
    alts = tag_values(body, "flag alt") |> split_modifier_values()

    cleaned =
      body
      |> String.replace(~r/<tinyboard [^>]+>.*?<\/tinyboard>/us, "")
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")
      |> String.trim()

    {cleaned, flags, alts}
  end

  defp tag_values(body, tag_name) do
    regex = Regex.compile!("<tinyboard #{Regex.escape(tag_name)}>(.*?)</tinyboard>", "us")

    Regex.scan(regex, body)
    |> Enum.map(fn [_, value] -> value end)
  end

  defp split_modifier_values(values) do
    values
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp count_files(row) do
    row["files"]
    |> List.wrap()
    |> Enum.reject(&blank_file?/1)
    |> length()
  end

  defp blank_file?(file) when is_map(file) do
    blank?(file["file"]) and blank?(file["file_path"]) and blank?(file["full_path"])
  end

  defp blank_file?(_), do: true

  defp deleted_legacy_file?(file) when is_map(file), do: file["file"] == "deleted"
  defp deleted_legacy_file?(_), do: false

  defp spoiler_thumb?(file) when is_map(file),
    do: file["thumb"] == "spoiler" or file["thumb_path"] == "spoiler"

  defp spoiler_thumb?(_), do: false

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp integer_or_nil(nil), do: nil
  defp integer_or_nil(value) when is_integer(value), do: value
  defp integer_or_nil(value) when is_binary(value), do: String.to_integer(value)

  defp truthy?(value), do: value in [true, 1, "1"]

  defp legacy_bump_at(%{"bump" => nil, "time" => time}), do: from_unix_usec(time)

  defp legacy_bump_at(%{"bump" => bump}), do: from_unix_usec(bump)

  defp shuffle_all_threads(repo) do
    now = now_usec()

    thread_ids =
      repo.all(from post in Post, where: is_nil(post.thread_id), select: post.id)
      |> Enum.shuffle()

    Enum.with_index(thread_ids)
    |> Enum.each(fn {thread_id, index} ->
      repo.update_all(
        from(post in Post, where: post.id == ^thread_id),
        set: [bump_at: DateTime.add(now, -index, :second)]
      )
    end)

    :ok
  end

  defp from_unix_usec(seconds) when is_integer(seconds) do
    DateTime.from_unix!(seconds * 1_000_000, :microsecond)
  end

  defp now_usec do
    DateTime.utc_now()
    |> DateTime.to_unix(:microsecond)
    |> DateTime.from_unix!(:microsecond)
  end

  defp rebuild_all_boards(repo) do
    instance_config = Settings.current_instance_config()

    Boards.list_boards(repo: repo)
    |> Enum.each(fn board ->
      runtime_board = Boards.BoardRecord.to_board(board)

      config =
        Config.compose(nil, instance_config, board.config_overrides || %{}, board: runtime_board)

      Build.rebuild_board(board, repo: repo, config: config)
    end)

    :ok
  end
end
