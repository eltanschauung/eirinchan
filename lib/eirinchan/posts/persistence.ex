defmodule Eirinchan.Posts.Persistence do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Cite
  alias Eirinchan.Posts.NntpReference
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PostFile
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
           with {:ok, post} <- insert_post(board, thread, attrs, repo, config, now),
                {:ok, post} <- maybe_store_uploads(board, post, upload_entries, repo, config),
                :ok <- store_citations(board, post, repo),
                :ok <- after_insert.() do
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

  defp store_primary_upload(board, post, %{upload: upload, metadata: metadata}, repo, config) do
    case Uploads.store(board, post, upload, config, metadata) do
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
      case Uploads.store(
             board,
             post,
             entry.upload,
             config,
             entry.metadata,
             Integer.to_string(position)
           ) do
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
      |> extract_cited_post_ids()
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

  defp extract_cited_post_ids(nil), do: []

  defp extract_cited_post_ids(body) do
    Regex.scan(~r/>>(\d+)/u, body)
    |> Enum.map(fn [_, id] -> String.to_integer(id) end)
    |> Enum.uniq()
  end

  defp existing_cited_post_ids([], _board_id, _repo), do: []

  defp existing_cited_post_ids(target_ids, board_id, repo) do
    repo.all(
      from post in Post,
        where: post.board_id == ^board_id and post.id in ^target_ids,
        select: post.id
    )
  end

  defp cleanup_stored_files(metadata_list) do
    Enum.each(metadata_list, fn metadata ->
      Uploads.remove(metadata.file_path)
      Uploads.remove(metadata.thumb_path)
    end)
  end

  defp request_ip_string(_attrs, %{ip_nulling: true}), do: nil
  defp request_ip_string(attrs, _config), do: Map.get(attrs, "ip_subnet")

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
