defmodule Eirinchan.Posts.Persistence do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.AprilFoolsTeams
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Cite
  alias Eirinchan.Posts.NntpReference
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Posts
  alias Eirinchan.Uploads

  @spec create_post_record(
          BoardRecord.t(),
          Post.t() | nil,
          map(),
          module(),
          map(),
          DateTime.t(),
          (() -> :ok)
        ) ::
          {:ok, Post.t()} | {:error, term()}
  def create_post_record(%BoardRecord{} = board, thread, attrs, repo, config, now, after_insert) do
    upload_entries = Map.get(attrs, "__upload_entries__", [])

    case repo.transaction(fn ->
           with {:ok, locked_board} <- lock_board(board, repo),
                {:ok, attrs} <- allocate_public_id(locked_board, attrs, repo),
                {:ok, post} <- insert_post(locked_board, thread, attrs, repo, config, now),
                {:ok, post} <- maybe_store_uploads(board, post, upload_entries, repo, config),
                :ok <- maybe_increment_april_fools_team(post, config, repo),
                :ok <- store_citations(locked_board, post, repo),
                :ok <- after_insert.(),
                :ok <- Posts.sync_thread_metrics(locked_board, post.thread_id || post.id, repo: repo) do
             post
           else
             {:error, reason} -> repo.rollback(reason)
           end
         end) do
      {:ok, post} -> {:ok, post}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_post(board, nil, attrs, repo, config, now) do
    attrs =
      attrs
      |> Map.put("board_id", board.id)
      |> Map.put("thread_id", nil)
      |> Map.update("body", "", &(&1 || ""))
      |> Map.put("ip_subnet", request_ip_string(attrs, config))
      |> Map.put("bump_at", now)
      |> Map.put("sticky", false)
      |> Map.put("locked", false)
      |> Map.put("cycle", false)
      |> Map.put("sage", false)
      |> Map.put("slug", maybe_slugify(attrs, config))

    %Post{}
    |> Post.create_changeset(attrs)
    |> repo.insert()
  end

  defp insert_post(board, thread, attrs, repo, config, _now) do
    attrs =
      attrs
      |> Map.put("board_id", board.id)
      |> Map.put("thread_id", thread.id)
      |> Map.update("body", "", &(&1 || ""))
      |> Map.put("ip_subnet", request_ip_string(attrs, config))

    %Post{}
    |> Post.create_changeset(attrs)
    |> repo.insert()
  end

  defp maybe_store_uploads(_board, %Post{} = post, [], repo, _config),
    do: {:ok, repo.preload(post, :extra_files)}

  defp maybe_store_uploads(board, %Post{} = post, [primary | rest], repo, config) do
    with {:ok, updated_post, stored_files} <-
           store_primary_upload(board, post, primary, repo, config),
         {:ok, _extra_files, _stored_files} <-
           store_extra_uploads(board, updated_post, rest, repo, config, stored_files) do
      {:ok, repo.preload(updated_post, :extra_files)}
    else
      {:error, reason, stored_files} ->
        cleanup_stored_files(stored_files)
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_primary_upload(board, post, %{metadata: metadata}, repo, config) do
    case Uploads.finalize(board, post, config, metadata) do
      {:ok, stored_metadata} ->
        case post |> Post.create_changeset(stored_metadata) |> repo.update() do
          {:ok, updated_post} ->
            {:ok, updated_post, [stored_metadata]}

          {:error, %Ecto.Changeset{} = changeset} ->
            cleanup_stored_files([stored_metadata])
            {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_extra_uploads(_board, _post, [], _repo, _config, stored_files),
    do: {:ok, [], stored_files}

  defp store_extra_uploads(board, post, entries, repo, config, stored_files) do
    Enum.with_index(entries, 1)
    |> Enum.reduce_while({:ok, [], stored_files}, fn {entry, position}, {:ok, inserted, stored} ->
      case Uploads.finalize(board, post, config, entry.metadata, Integer.to_string(position)) do
        {:ok, stored_metadata} ->
          attrs =
            stored_metadata
            |> Map.put(:post_id, post.id)
            |> Map.put(:position, position)

          case %PostFile{} |> PostFile.create_changeset(attrs) |> repo.insert() do
            {:ok, post_file} ->
              {:cont, {:ok, [post_file | inserted], [stored_metadata | stored]}}

            {:error, %Ecto.Changeset{} = changeset} ->
              {:halt, {:error, changeset, [stored_metadata | stored]}}
          end

        {:error, reason} ->
          {:halt, {:error, reason, stored}}
      end
    end)
    |> case do
      {:ok, files, stored} -> {:ok, Enum.reverse(files), stored}
      {:error, reason, stored} -> {:error, reason, stored}
    end
  end

  def store_citations(board, post, repo) do
    target_post_ids =
      post.body
      |> extract_cited_public_ids()
      |> existing_cited_post_ids(board.id, repo)

    Enum.reduce_while(target_post_ids, :ok, fn target_post_id, :ok ->
      with {:ok, _cite} <-
             %Cite{}
             |> Cite.changeset(%{post_id: post.id, target_post_id: target_post_id})
             |> repo.insert(on_conflict: :nothing, conflict_target: [:post_id, :target_post_id]),
           {:ok, _reference} <-
             %NntpReference{}
             |> NntpReference.changeset(%{post_id: post.id, target_post_id: target_post_id})
             |> repo.insert(on_conflict: :nothing, conflict_target: [:post_id, :target_post_id]) do
        {:cont, :ok}
      else
        {:error, _changeset} -> {:halt, {:error, :cite_insert_failed}}
      end
    end)
  end

  defp extract_cited_public_ids(nil), do: []

  defp extract_cited_public_ids(body) do
    Regex.scan(~r/>>(\d+)/u, body)
    |> Enum.map(fn [_, id] -> String.to_integer(id) end)
    |> Enum.uniq()
  end

  defp existing_cited_post_ids([], _board_id, _repo), do: []

  defp existing_cited_post_ids(target_public_ids, board_id, repo) do
    repo.all(
      from post in Post,
        where: post.board_id == ^board_id and post.public_id in ^target_public_ids,
        select: post.id
    )
  end

  defp lock_board(%BoardRecord{} = board, repo) do
    case repo.one(from board_record in BoardRecord, where: board_record.id == ^board.id, lock: "FOR UPDATE") do
      %BoardRecord{} = locked_board -> {:ok, locked_board}
      _ -> {:error, :board_not_found}
    end
  end

  defp allocate_public_id(%BoardRecord{} = board, attrs, repo) do
    explicit_public_id =
      case Map.get(attrs, "public_id") || Map.get(attrs, :public_id) do
        value when is_integer(value) and value > 0 -> value
        value when is_binary(value) ->
          case Integer.parse(value) do
            {parsed, ""} when parsed > 0 -> parsed
            _ -> nil
          end

        _ ->
          nil
      end

    public_id = explicit_public_id || board.next_public_post_id || 1
    next_public_post_id = max((board.next_public_post_id || 1), public_id + 1)

    case board
         |> Ecto.Changeset.change(next_public_post_id: next_public_post_id)
         |> repo.update() do
      {:ok, _updated_board} ->
        {:ok, put_param(attrs, "public_id", public_id)}

      {:error, _changeset} ->
        {:error, :board_counter_update_failed}
    end
  end

  defp put_param(attrs, string_key, value) when is_map(attrs) do
    if Enum.all?(Map.keys(attrs), &is_atom/1) do
      Map.put(attrs, String.to_existing_atom(string_key), value)
    else
      Map.put(attrs, string_key, value)
    end
  rescue
    ArgumentError -> Map.put(attrs, String.to_atom(string_key), value)
  end

  defp cleanup_stored_files(metadata_list) do
    Enum.each(metadata_list, fn metadata ->
      Uploads.remove(metadata.file_path)
      Uploads.remove(metadata.thumb_path)
    end)
  end

  defp request_ip_string(attrs, %{ip_nulling: true} = config) do
    case Map.get(config, :ip_nulling_flags, 0) do
      threshold when is_integer(threshold) and threshold > 0 ->
        if submitted_flag_length(attrs) >= threshold, do: nil, else: Map.get(attrs, "ip_subnet")

      _ ->
        nil
    end
  end

  defp request_ip_string(attrs, _config), do: Map.get(attrs, "ip_subnet")

  defp maybe_increment_april_fools_team(%Post{} = post, config, repo) do
    team = post.team

    if AprilFoolsTeams.enabled?(config) and is_integer(team) do
      AprilFoolsTeams.increment_post_count(team, AprilFoolsTeams.image_post?(post), repo)
    else
      :ok
    end
  end

  defp submitted_flag_length(attrs) do
    attrs
    |> submitted_flag_value()
    |> case do
      value when is_binary(value) -> value |> String.trim() |> String.length()
      _ -> 0
    end
  end

  defp submitted_flag_value(attrs) do
    Map.get(attrs, "user_flag") || Map.get(attrs, "flags")
  end

  defp maybe_slugify(attrs, config) do
    if config.slugify do
      attrs
      |> Map.get("subject")
      |> case do
        nil ->
          nil

        subject ->
          slug =
            subject
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9]+/u, "-")
            |> String.trim("-")
            |> String.slice(0, config.slug_max_size)

          if slug == "", do: nil, else: slug
      end
    else
      nil
    end
  end
end
