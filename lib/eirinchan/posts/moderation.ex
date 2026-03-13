defmodule Eirinchan.Posts.Moderation do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Build
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts
  alias Eirinchan.Posts.ThreadLookup, as: PostsThreadLookup
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Uploads

  @deleted_file_sentinel "deleted"

  @spec moderate_delete_post(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, :post_not_found | Ecto.Changeset.t()}
  def moderate_delete_post(%BoardRecord{} = board, post_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, normalized_post_id} <- PostsThreadLookup.normalize_thread_id(post_id),
         %Post{} = post <- repo.get_by(Post, id: normalized_post_id, board_id: board.id),
         file_paths <- post_delete_file_paths(post, repo),
         {:ok, _deleted_post} <- repo.delete(post) do
      Enum.each(file_paths, &Uploads.remove/1)

      result =
        if is_nil(post.thread_id) do
          _ = Build.rebuild_after_delete(board, {:thread, post}, config: config, repo: repo)
          %{deleted_post_id: post.id, thread_id: post.id, thread_deleted: true}
        else
          _ =
            Build.rebuild_after_delete(board, {:reply, post.thread_id}, config: config, repo: repo)

          %{deleted_post_id: post.id, thread_id: post.thread_id, thread_deleted: false}
        end

      {:ok, result}
    else
      _ -> {:error, :post_not_found}
    end
  end

  @spec moderate_delete_posts_by_ip(BoardRecord.t() | [BoardRecord.t()], String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def moderate_delete_posts_by_ip(board_or_boards, ip_subnet, opts \\ [])

  def moderate_delete_posts_by_ip(%BoardRecord{} = board, ip_subnet, opts) do
    moderate_delete_posts_by_ip([board], ip_subnet, opts)
  end

  def moderate_delete_posts_by_ip(boards, ip_subnet, opts) when is_list(boards) do
    repo = Keyword.get(opts, :repo, Repo)
    config_by_board = Keyword.get(opts, :config_by_board, %{})
    normalized_ip = normalize_request_ip(ip_subnet)
    board_ids = Enum.map(boards, & &1.id)

    posts =
      if is_nil(normalized_ip) do
        []
      else
        repo.all(
          from post in Post,
            where: post.board_id in ^board_ids and post.ip_subnet == ^normalized_ip,
            order_by: [desc: post.thread_id, desc: post.id]
        )
      end

    Enum.each(posts, fn post ->
      board = Enum.find(boards, &(&1.id == post.board_id))

      config =
        Map.get(config_by_board, board.id) || Keyword.get(opts, :config) || Config.compose()

      _ = moderate_delete_post(board, post.id, Keyword.merge(opts, config: config, repo: repo))
    end)

    {:ok,
     %{
       deleted_post_ids: Enum.map(posts, & &1.id),
       deleted_threads: posts |> Enum.filter(&is_nil(&1.thread_id)) |> Enum.map(& &1.id),
       count: length(posts),
       board_ids: posts |> Enum.map(& &1.board_id) |> Enum.uniq() |> Enum.sort()
     }}
  end

  @spec delete_post_files(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_post_files(%BoardRecord{} = board, post_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, post} <- Posts.get_post(board, post_id, repo: repo) do
      file_paths = post_delete_file_paths(post, repo)

      case repo.transaction(fn ->
             with {:ok, updated_post} <-
                    post
                    |> Post.create_changeset(deleted_file_attrs(post))
                    |> repo.update(),
                  :ok <- mark_extra_files_deleted(post.id, repo) do
               repo.preload(updated_post, :extra_files, force: true)
             else
               {:error, reason} -> repo.rollback(reason)
             end
           end) do
        {:ok, updated_post} ->
          Enum.each(file_paths, &Uploads.remove/1)
          _ = Build.rebuild_after_post_update(board, updated_post, config: config, repo: repo)
          {:ok, updated_post}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec delete_post_file(BoardRecord.t(), String.t() | integer(), non_neg_integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_post_file(%BoardRecord{} = board, post_id, file_index, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, post} <- Posts.get_post(board, post_id, repo: repo),
         {:ok, normalized_index} <- normalize_file_index(file_index),
         {:ok, updated_post, file_paths} <- delete_single_post_file(post, normalized_index, repo) do
      Enum.each(file_paths, &Uploads.remove/1)
      _ = Build.rebuild_after_post_update(board, updated_post, config: config, repo: repo)
      {:ok, updated_post}
    else
      {:error, :invalid_file_index} -> {:error, :not_found}
      other -> other
    end
  end

  @spec spoilerize_post_files(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def spoilerize_post_files(%BoardRecord{} = board, post_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, post} <- Posts.get_post(board, post_id, repo: repo) do
      case repo.transaction(fn ->
             {:ok, updated_post} =
               post
               |> Post.create_changeset(%{spoiler: has_primary_file?(post)})
               |> repo.update()

             from(post_file in PostFile, where: post_file.post_id == ^post.id)
             |> repo.update_all(set: [spoiler: true])

             repo.preload(updated_post, :extra_files, force: true)
           end) do
        {:ok, updated_post} ->
          if has_primary_file?(updated_post) do
            :ok = Uploads.write_spoiler_thumbnail(updated_post.thumb_path, config)
          end

          Enum.each(updated_post.extra_files, fn post_file ->
            :ok = Uploads.write_spoiler_thumbnail(post_file.thumb_path, config)
          end)

          _ = Build.rebuild_after_post_update(board, updated_post, config: config, repo: repo)
          {:ok, updated_post}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec spoilerize_post_file(BoardRecord.t(), String.t() | integer(), non_neg_integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def spoilerize_post_file(%BoardRecord{} = board, post_id, file_index, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, post} <- Posts.get_post(board, post_id, repo: repo),
         {:ok, normalized_index} <- normalize_file_index(file_index),
         {:ok, updated_post, thumb_paths} <- spoiler_single_post_file(post, normalized_index, repo) do
      Enum.each(thumb_paths, &Uploads.write_spoiler_thumbnail(&1, config))
      _ = Build.rebuild_after_post_update(board, updated_post, config: config, repo: repo)
      {:ok, updated_post}
    else
      {:error, :invalid_file_index} -> {:error, :not_found}
      other -> other
    end
  end

  @spec move_thread(BoardRecord.t(), String.t() | integer(), BoardRecord.t(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | :upload_failed | Ecto.Changeset.t()}
  def move_thread(%BoardRecord{} = source_board, thread_id, %BoardRecord{} = target_board, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    source_config = Keyword.get(opts, :source_config, Keyword.get(opts, :config, Config.compose()))
    target_config = Keyword.get(opts, :target_config, source_config)

    with {:ok, [thread | replies]} <- Posts.get_thread(source_board, thread_id, repo: repo) do
      posts = [thread | replies]
      file_moves = move_file_operations(posts, source_board, target_board)

      case apply_file_moves(file_moves) do
        :ok ->
          case repo.transaction(fn ->
                 updated_posts =
                   Enum.reduce_while(posts, [], fn post, acc ->
                     attrs = %{
                       board_id: target_board.id,
                       file_path: remap_board_path(post.file_path, source_board, target_board),
                       thumb_path: remap_board_path(post.thumb_path, source_board, target_board)
                     }

                     with {:ok, updated_post} <- post |> Post.create_changeset(attrs) |> repo.update(),
                          :ok <- move_extra_files(post, source_board, target_board, repo) do
                       {:cont, [updated_post | acc]}
                     else
                       {:error, reason} -> {:halt, repo.rollback(reason)}
                     end
                   end)

                 Enum.each(updated_posts, fn updated_post ->
                   case Posts.replace_citations(target_board, updated_post, repo) do
                     :ok -> :ok
                     {:error, reason} -> repo.rollback(reason)
                   end
                 end)

                 Enum.find(updated_posts, &is_nil(&1.thread_id))
               end) do
            {:ok, moved_thread} ->
              _ = Build.rebuild_after_delete(source_board, {:thread, thread}, config: source_config, repo: repo)
              _ = Build.rebuild_after_post(target_board, moved_thread, config: target_config, repo: repo)
              {:ok, repo.preload(moved_thread, :extra_files, force: true)}

            {:error, reason} ->
              _ = reverse_file_moves(file_moves)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec move_reply(BoardRecord.t(), String.t() | integer(), BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | :upload_failed | Ecto.Changeset.t()}
  def move_reply(%BoardRecord{} = source_board, post_id, %BoardRecord{} = target_board, target_thread_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    source_config = Keyword.get(opts, :source_config, Keyword.get(opts, :config, Config.compose()))
    target_config = Keyword.get(opts, :target_config, source_config)

    with {:ok, reply} <- Posts.get_post(source_board, post_id, repo: repo),
         false <- is_nil(reply.thread_id),
         {:ok, target_thread} <- PostsThreadLookup.fetch_thread(target_board, target_thread_id, repo) do
      file_moves = move_file_operations([reply], source_board, target_board)

      case apply_file_moves(file_moves) do
        :ok ->
          case repo.transaction(fn ->
                 attrs = %{
                   board_id: target_board.id,
                   thread_id: target_thread.id,
                   file_path: remap_board_path(reply.file_path, source_board, target_board),
                   thumb_path: remap_board_path(reply.thumb_path, source_board, target_board)
                 }

                 with {:ok, updated_reply} <- reply |> Post.create_changeset(attrs) |> repo.update(),
                      :ok <- move_extra_files(reply, source_board, target_board, repo),
                      :ok <- Posts.replace_citations(target_board, updated_reply, repo) do
                   updated_reply
                 else
                   {:error, reason} -> repo.rollback(reason)
                 end
               end) do
            {:ok, moved_reply} ->
              _ = Build.rebuild_after_delete(source_board, {:reply, reply.thread_id}, config: source_config, repo: repo)
              _ = Build.rebuild_after_post(target_board, moved_reply, config: target_config, repo: repo)
              {:ok, repo.preload(moved_reply, :extra_files, force: true)}

            {:error, reason} ->
              _ = reverse_file_moves(file_moves)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      true -> {:error, :not_found}
      {:error, :thread_not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_file_index(file_index) when is_integer(file_index) and file_index >= 0, do: {:ok, file_index}

  defp normalize_file_index(file_index) when is_binary(file_index) do
    case Integer.parse(file_index) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, :invalid_file_index}
    end
  end

  defp normalize_file_index(_), do: {:error, :invalid_file_index}

  defp normalize_request_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp normalize_request_ip({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp normalize_request_ip(ip) when is_binary(ip), do: String.trim(ip)
  defp normalize_request_ip(_ip), do: nil

  defp delete_single_post_file(%Post{} = post, file_index, repo) do
    extra = extra_files_for_post(post, repo)

    cond do
      file_index == 0 and path_present?(post.file_path) ->
        delete_primary_post_file(post, extra, repo)

      file_index > 0 ->
        delete_extra_post_file(post, extra, file_index, repo)

      true ->
        {:error, :not_found}
    end
  end

  defp spoiler_single_post_file(%Post{} = post, file_index, repo) do
    extra = extra_files_for_post(post, repo)

    cond do
      file_index == 0 and path_present?(post.file_path) ->
        case repo.transaction(fn ->
               case post |> Post.create_changeset(%{spoiler: true}) |> repo.update() do
                 {:ok, updated_post} -> repo.preload(updated_post, :extra_files, force: true)
                 {:error, reason} -> repo.rollback(reason)
               end
             end) do
          {:ok, updated_post} -> {:ok, updated_post, [updated_post.thumb_path]}
          {:error, reason} -> {:error, reason}
        end

      file_index > 0 ->
        case Enum.find(extra, &(&1.position == file_index)) do
          nil ->
            {:error, :not_found}

          target ->
            case repo.transaction(fn ->
                   case target |> PostFile.create_changeset(%{spoiler: true}) |> repo.update() do
                     {:ok, _updated_file} ->
                       post
                       |> repo.preload(:extra_files, force: true)

                     {:error, reason} ->
                       repo.rollback(reason)
                   end
                 end) do
              {:ok, updated_post} -> {:ok, updated_post, [target.thumb_path]}
              {:error, reason} -> {:error, reason}
            end
        end

      true ->
        {:error, :not_found}
    end
  end

  defp delete_primary_post_file(%Post{} = post, [], repo) do
    file_paths = primary_file_delete_paths(post)

    case repo.transaction(fn ->
           case post |> Post.create_changeset(deleted_file_attrs(post)) |> repo.update() do
             {:ok, updated_post} -> repo.preload(updated_post, :extra_files, force: true)
             {:error, reason} -> repo.rollback(reason)
           end
         end) do
      {:ok, updated_post} -> {:ok, updated_post, file_paths}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_primary_post_file(%Post{} = post, [_promotion | _rest], repo) do
    file_paths = primary_file_delete_paths(post)

    case repo.transaction(fn ->
           case post |> Post.create_changeset(deleted_file_attrs(post)) |> repo.update() do
             {:ok, updated_post} ->
               repo.preload(updated_post, :extra_files, force: true)

             {:error, reason} ->
               repo.rollback(reason)
           end
         end) do
      {:ok, updated_post} -> {:ok, updated_post, file_paths}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_extra_post_file(%Post{} = post, extra_files, file_index, repo) do
    case Enum.find(extra_files, &(&1.position == file_index)) do
      nil ->
        {:error, :not_found}

      target ->
        file_paths = file_delete_paths(target)

        case repo.transaction(fn ->
               case target |> PostFile.create_changeset(deleted_file_attrs(target)) |> repo.update() do
                 {:ok, _updated_file} ->
                   repo.preload(post, :extra_files, force: true)

                 {:error, reason} ->
                   repo.rollback(reason)
               end
             end) do
          {:ok, updated_post} -> {:ok, updated_post, file_paths}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp deleted_file_attrs(file_like) do
    %{
      file_name: Map.get(file_like, :file_name),
      file_path: @deleted_file_sentinel,
      thumb_path: nil,
      file_size: Map.get(file_like, :file_size),
      file_type: Map.get(file_like, :file_type),
      file_md5: Map.get(file_like, :file_md5),
      image_width: Map.get(file_like, :image_width),
      image_height: Map.get(file_like, :image_height),
      spoiler: false
    }
  end

  defp mark_extra_files_deleted(post_id, repo) do
    post_files =
      repo.all(
        from post_file in PostFile,
          where: post_file.post_id == ^post_id
      )

    Enum.reduce_while(post_files, :ok, fn post_file, :ok ->
      case post_file |> PostFile.create_changeset(deleted_file_attrs(post_file)) |> repo.update() do
        {:ok, _updated_post_file} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp extra_files_for_post(%Post{} = post, repo) do
    post
    |> repo.preload(:extra_files, force: true)
    |> Map.get(:extra_files)
    |> Enum.sort_by(& &1.position)
  end

  defp primary_file_delete_paths(%Post{} = post) do
    [post.file_path, post.thumb_path]
    |> Enum.filter(&path_present?/1)
  end

  defp file_delete_paths(file) do
    [file.file_path, file.thumb_path]
    |> Enum.filter(&path_present?/1)
  end

  defp path_present?(value) when is_binary(value) do
    trimmed = String.trim(value)
    trimmed != "" and trimmed != @deleted_file_sentinel
  end

  defp path_present?(value), do: not is_nil(value)

  defp post_delete_file_paths(%Post{thread_id: nil, id: thread_id} = thread, repo) do
    reply_paths =
      repo.all(
        from post in Post,
          where: post.thread_id == ^thread_id,
          select: {post.file_path, post.thumb_path}
      )

    extra_paths =
      repo.all(
        from post_file in PostFile,
          join: post in Post,
          on: post_file.post_id == post.id,
          where: post.id == ^thread_id or post.thread_id == ^thread_id,
          select: {post_file.file_path, post_file.thumb_path}
      )

    [
      thread.file_path,
      thread.thumb_path
      | Enum.flat_map(reply_paths ++ extra_paths, fn {file_path, thumb_path} ->
          [file_path, thumb_path]
        end)
    ]
    |> Enum.filter(&path_present?/1)
  end

  defp post_delete_file_paths(%Post{} = post, repo) do
    extra_paths =
      repo.all(
        from post_file in PostFile,
          where: post_file.post_id == ^post.id,
          select: {post_file.file_path, post_file.thumb_path}
      )

    [
      post.file_path,
      post.thumb_path
      | Enum.flat_map(extra_paths, fn {file_path, thumb_path} -> [file_path, thumb_path] end)
    ]
    |> Enum.filter(&path_present?/1)
  end

  defp has_primary_file?(%Post{file_path: file_path}) when is_binary(file_path),
    do: file_path != "" and file_path != @deleted_file_sentinel

  defp has_primary_file?(_post), do: false

  defp extra_files(%{extra_files: %Ecto.Association.NotLoaded{}}), do: []
  defp extra_files(%{extra_files: files}) when is_list(files), do: files
  defp extra_files(_post), do: []

  defp move_extra_files(post, source_board, target_board, repo) do
    Enum.reduce_while(extra_files(post), :ok, fn post_file, :ok ->
      attrs = %{
        file_path: remap_board_path(post_file.file_path, source_board, target_board),
        thumb_path: remap_board_path(post_file.thumb_path, source_board, target_board)
      }

      case post_file |> PostFile.create_changeset(attrs) |> repo.update() do
        {:ok, _updated_post_file} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp move_file_operations(posts, source_board, target_board) do
    posts
    |> Enum.flat_map(fn post ->
      primary_moves = [
        {post.file_path, remap_board_path(post.file_path, source_board, target_board)},
        {post.thumb_path, remap_board_path(post.thumb_path, source_board, target_board)}
      ]

      extra_moves =
        post
        |> extra_files()
        |> Enum.flat_map(fn post_file ->
          [
            {post_file.file_path, remap_board_path(post_file.file_path, source_board, target_board)},
            {post_file.thumb_path, remap_board_path(post_file.thumb_path, source_board, target_board)}
          ]
        end)

      primary_moves ++ extra_moves
    end)
    |> Enum.uniq()
    |> Enum.reject(fn {source, destination} ->
      is_nil(source) or is_nil(destination) or source == destination
    end)
  end

  defp apply_file_moves(file_moves) do
    Enum.reduce_while(file_moves, {:ok, []}, fn {source, destination}, {:ok, moved} ->
      case Uploads.relocate(source, destination) do
        :ok -> {:cont, {:ok, [{source, destination} | moved]}}
        {:error, reason} -> {:halt, {:error, reason, moved}}
      end
    end)
    |> case do
      {:ok, _moved} ->
        :ok

      {:error, reason, moved} ->
        _ = reverse_file_moves(moved)
        {:error, reason}
    end
  end

  defp reverse_file_moves(file_moves) do
    Enum.each(file_moves, fn {source, destination} ->
      _ = Uploads.relocate(destination, source)
    end)

    :ok
  end

  defp remap_board_path(nil, _source_board, _target_board), do: nil

  defp remap_board_path(path, %BoardRecord{uri: source_uri}, %BoardRecord{uri: target_uri})
       when is_binary(path) do
    String.replace_prefix(path, "/#{source_uri}/", "/#{target_uri}/")
  end

end
