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

  @page_script Path.expand("../../priv/scripts/export_live_vichan_page.php", __DIR__)
  @thread_script Path.expand("../../priv/scripts/export_live_vichan_thread.php", __DIR__)

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

  def import_thread(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    source_root = Keyword.get(opts, :source_root, "/path/to/vichan")
    board_uri = Keyword.get(opts, :board, "bant")
    thread_id = Keyword.fetch!(opts, :thread_id)

    with {:ok, payload} <- export_live_thread(source_root, board_uri, thread_id),
         {:ok, board} <- ensure_board(payload["board"], repo),
         {:ok, result} <- import_payload(board, payload, repo, source_root),
         :ok <- rebuild_board(board, repo) do
      {:ok,
       Map.merge(result, %{
         board: board.uri,
         build_root: Build.board_root(),
         live_thread_id: thread_id,
         imported_public_id: result.op.public_id
       })}
    end
  end

  defp export_live_page(source_root, board_uri, limit) do
    export_with_script(@page_script, source_root, board_uri, limit)
  end

  defp export_live_thread(source_root, board_uri, thread_id) do
    export_with_script(@thread_script, source_root, board_uri, thread_id)
  end

  defp export_with_script(script, source_root, board_uri, value) do
    case System.cmd("php", [script, source_root, board_uri, Integer.to_string(value)],
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
    config = board_runtime_config(board)

    grouped =
      payload["posts"]
      |> Enum.group_by(fn row -> row["thread"] || row["id"] end)

    imported =
      payload["thread_ids"]
      |> Enum.map(fn legacy_thread_id ->
        import_thread_rows(
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
          Enum.reduce(imported, %{threads: 0, replies: 0, files: 0, op: nil, post_map: %{}}, fn {:ok, row},
                                                                                                  acc ->
            %{
              threads: acc.threads + 1,
              replies: acc.replies + row.replies,
              files: acc.files + row.files,
              op: acc.op || row.op,
              post_map: Map.merge(acc.post_map, row.post_map)
            }
          end)

        :ok =
          rewrite_imported_citations(
            board,
            grouped |> Map.values() |> List.flatten(),
            merged.post_map,
            repo
          )

        {:ok, Map.drop(merged, [:post_map])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_thread_rows(
         %BoardRecord{} = board,
         [op | replies],
         repo,
         config,
         source_root,
         legacy_thread_id
       ) do
    case existing_thread_map(board, [op | replies], repo, legacy_thread_id) do
      {:ok, post_map} ->
        {:ok,
         %{
           op: Map.fetch!(post_map, op["id"]),
           replies: length(replies),
           files: count_files(op) + Enum.sum(Enum.map(replies, &count_files/1)),
           post_map: post_map
         }}

      :error ->
        repo.transaction(
          fn ->
            locked_board =
              repo.one!(
                from board_record in BoardRecord,
                  where: board_record.id == ^board.id,
                  lock: "FOR UPDATE"
              )

            {inserted_op, locked_board} =
              insert_post(board, locked_board, nil, op, repo, config, source_root)

            {post_map, _board_after, reply_count, file_count} =
              Enum.reduce(
                replies,
                {%{legacy_thread_id => inserted_op, op["id"] => inserted_op}, locked_board, 0,
                 count_files(op)},
                fn reply, {map, board_acc, count, files} ->
                  {inserted_reply, updated_board} =
                    insert_post(board, board_acc, inserted_op, reply, repo, config, source_root)

                  {Map.put(map, reply["id"], inserted_reply), updated_board, count + 1,
                   files + count_files(reply)}
                end
              )

            %{
              op: inserted_op,
              replies: reply_count,
              files: file_count,
              post_map: post_map
            }
          end,
          timeout: :infinity
        )
        |> case do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
    end
  rescue
    error -> {:error, error}
  end

  defp existing_thread_map(%BoardRecord{} = board, [op | replies], repo, legacy_thread_id) do
    inserted_at = unix_second_datetime(op["time"])
    op_slug = blank_to_nil(op["slug"])
    {op_body, _codes, _alts} = extract_body_and_flags(op["body_nomarkup"] || op["body"] || "")

    query =
      from post in Post,
        where:
          post.board_id == ^board.id and is_nil(post.thread_id) and post.inserted_at == ^inserted_at

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
              {legacy_reply["id"], existing_reply}
            end)

          post_map =
            Map.merge(%{legacy_thread_id => existing_op, op["id"] => existing_op}, reply_map)

          :ok = backfill_legacy_import_ids(post_map, legacy_thread_id, op, replies, repo)

          {:ok, post_map}
        else
          :error
        end

      nil ->
        :error
    end
  end

  defp insert_post(%BoardRecord{} = board, locked_board, thread, legacy_row, repo, config, source_root) do
    {body, flag_codes, flag_alts} =
      extract_body_and_flags(legacy_row["body_nomarkup"] || legacy_row["body"] || "")

    inserted_at = unix_second_datetime(legacy_row["time"])
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

    public_id = locked_board.next_public_post_id || 1

    {:ok, updated_board} =
      locked_board
      |> Ecto.Changeset.change(next_public_post_id: public_id + 1)
      |> repo.update()

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
        public_id: public_id,
        legacy_import_id: legacy_row["id"],
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

    {post, updated_board}
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

      if File.exists?(source_abs) do
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
            legacy_file["thumb"] || Path.basename(stored_name)
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

        :ok =
          case Uploads.regenerate_thumbnail(file_abs, thumb_abs, config, metadata, op?) do
            :ok ->
              :ok

            {:error, _reason} ->
              restore_live_thumbnail(board, legacy_file, source_root, file_abs, thumb_abs, config)
          end

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
      else
        missing_source_asset_attrs(legacy_file)
      end
    end
  end

  defp missing_source_asset_attrs(legacy_file) do
    %{
      file_name: legacy_file["filename"] || legacy_file["name"] || legacy_file["file"] || "deleted",
      file_path: "deleted",
      thumb_path: nil,
      file_size: integer_or_nil(legacy_file["size"]),
      file_type:
        legacy_file["type"] || MIME.from_path(legacy_file["filename"] || "") ||
          "application/octet-stream",
      file_md5: legacy_file["hash"] || "deleted",
      image_width: integer_or_nil(legacy_file["width"]),
      image_height: integer_or_nil(legacy_file["height"]),
      spoiler: truthy?(legacy_file["spoiler"]) or spoiler_thumb?(legacy_file)
    }
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

  defp thumb_source_rel(%BoardRecord{} = board, legacy_file) do
    cond do
      spoiler_thumb?(legacy_file) ->
        nil

      is_binary(legacy_file["thumb_path"]) and legacy_file["thumb_path"] not in ["", "spoiler"] ->
        String.trim_leading(legacy_file["thumb_path"], "/")

      is_binary(legacy_file["thumb"]) and legacy_file["thumb"] not in ["", "spoiler"] ->
        Path.join([board.uri, "thumb", legacy_file["thumb"]])

      true ->
        nil
    end
  end

  defp restore_live_thumbnail(
         %BoardRecord{} = board,
         legacy_file,
         source_root,
         file_abs,
         thumb_abs,
         config
       ) do
    cond do
      truthy?(legacy_file["spoiler"]) or spoiler_thumb?(legacy_file) ->
        File.cp!(Path.join(Application.app_dir(:eirinchan, "priv/static/static"), "spoiler.png"), thumb_abs)
        :ok

      true ->
        case thumb_source_rel(board, legacy_file) do
          nil ->
            {:error, :upload_failed}

          thumb_rel ->
            live_thumb_abs = Path.join(source_root, thumb_rel)

            if File.exists?(live_thumb_abs) do
              thumb_abs |> Path.dirname() |> File.mkdir_p!()
              File.cp!(live_thumb_abs, thumb_abs)
              :ok
            else
              {:error, :upload_failed}
            end
        end
    end
  end

  @doc false
  def rewrite_imported_citations(%BoardRecord{} = board, rows, post_map, repo \\ Repo) do
    cite_post_map = citation_post_map(board, rows, post_map, repo)

    Enum.each(rows, fn row ->
      new_post = Map.fetch!(post_map, row["id"])
      original_body = row["body_nomarkup"] || row["body"] || ""
      {clean_body, _codes, _alts} = extract_body_and_flags(original_body)
      rewritten = remap_cites(clean_body, cite_post_map)

      repo.update_all(from(post in Post, where: post.id == ^new_post.id), set: [body: rewritten])

      extract_cited_ids(clean_body)
      |> Enum.uniq()
      |> Enum.each(fn legacy_target_id ->
        case Map.get(cite_post_map, legacy_target_id) do
          %Post{} = target_post ->
            now = now_usec()

            repo.insert_all(
              "cites",
              [
                %{
                  post_id: new_post.id,
                  target_post_id: target_post.id,
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
                  post_id: new_post.id,
                  target_post_id: target_post.id,
                  inserted_at: now,
                  updated_at: now
                }
              ],
              on_conflict: :nothing
            )

          _ ->
            :ok
        end
      end)
    end)

    :ok
  end

  defp citation_post_map(%BoardRecord{} = board, rows, post_map, repo) do
    missing_ids =
      rows
      |> Enum.flat_map(fn row ->
        (row["body_nomarkup"] || row["body"] || "")
        |> extract_body_and_flags()
        |> elem(0)
        |> extract_cited_ids()
      end)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(post_map, &1))

    if missing_ids == [] do
      post_map
    else
      imported_posts =
        repo.all(
          from post in Post,
            where: post.board_id == ^board.id and post.legacy_import_id in ^missing_ids
        )
        |> Map.new(fn post -> {post.legacy_import_id, post} end)

      Map.merge(imported_posts, post_map)
    end
  end

  defp backfill_legacy_import_ids(post_map, legacy_thread_id, op, replies, repo) do
    updates =
      [{legacy_thread_id, legacy_thread_id}, {op["id"], op["id"]}]
      |> Enum.concat(Enum.map(replies, &{&1["id"], &1["id"]}))
      |> Enum.uniq()

    Enum.each(updates, fn {post_map_key, legacy_id} ->
      case Map.fetch(post_map, post_map_key) do
        {:ok, %Post{id: post_id}} ->
          repo.update_all(
            from(post in Post, where: post.id == ^post_id and is_nil(post.legacy_import_id)),
            set: [legacy_import_id: legacy_id]
          )

        :error ->
          :ok
      end
    end)

    :ok
  end

  defp remap_cites(body, post_map) when is_binary(body) do
    Regex.replace(~r/>>(\d+)/u, body, fn _, id ->
      case Map.get(post_map, String.to_integer(id)) do
        %Post{} = mapped -> ">>#{mapped.public_id}"
        _ -> ">>#{id}"
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

  defp integer_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp integer_or_nil(_), do: nil

  defp truthy?(value), do: value in [true, 1, "1", "true"]

  defp legacy_bump_at(%{"bump" => value}) when is_integer(value), do: unix_usec_datetime(value)
  defp legacy_bump_at(_), do: nil

  defp unix_second_datetime(value) when is_integer(value) do
    DateTime.from_unix!(value, :second)
    |> DateTime.truncate(:second)
  end

  defp unix_usec_datetime(value) when is_integer(value) do
    DateTime.from_unix!(value, :second)
    |> Map.put(:microsecond, {0, 6})
  end

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

  defp now_usec, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp rebuild_all_boards(repo) do
    Boards.list_boards(repo: repo)
    |> Enum.each(&rebuild_board(&1, repo))

    :ok
  end

  defp rebuild_board(board, repo) do
    config = board_runtime_config(board)
    Build.rebuild_board(board, repo: repo, config: config)
  end

  defp board_runtime_config(board) do
    instance_config = Settings.current_instance_config()
    runtime_board = Boards.BoardRecord.to_board(board)
    Config.compose(nil, instance_config, board.config_overrides || %{}, board: runtime_board)
  end
end
