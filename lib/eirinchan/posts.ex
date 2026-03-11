defmodule Eirinchan.Posts do
  @moduledoc """
  Minimal posting pipeline for OP and reply creation.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Antispam
  alias Eirinchan.AccessList
  alias Eirinchan.Bans
  alias Eirinchan.Build
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Captcha
  alias Eirinchan.DNSBL
  alias Eirinchan.GeoIp
  alias Eirinchan.Moderation
  alias Eirinchan.Moderation.ModUser
  alias Eirinchan.Posts.Cite
  alias Eirinchan.Posts.NntpReference
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.ThreadPaths
  alias Eirinchan.Uploads

  @spec create_post(BoardRecord.t(), map(), keyword()) ::
          {:ok, Post.t(), map()}
          | {:error,
             :thread_not_found
             | :invalid_post_mode
             | :invalid_referer
             | :invalid_embed
             | :dnsbl
             | :antispam
             | :invalid_captcha
             | :banned
             | :cite_insert_failed
             | :board_locked
             | :thread_locked
             | :body_required
             | :body_too_long
             | :too_many_lines
             | :invalid_user_flag
             | :reply_hard_limit
             | :image_hard_limit
             | :invalid_image
             | :image_too_large
             | :duplicate_file
             | :file_required
             | :invalid_file_type
             | :file_too_large
             | :access_list
             | :upload_failed}
          | {:error, Ecto.Changeset.t()}
  def create_post(%BoardRecord{} = board, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())
    request = Keyword.get(opts, :request, %{})
    attrs = normalize_attrs(attrs)

    with {:ok, attrs} <- normalize_embed(attrs, config),
         {:ok, attrs} <- prepare_uploads(attrs, config) do
      thread_param = blank_to_nil(Map.get(attrs, "thread"))
      op? = is_nil(thread_param)
      noko = noko?(attrs["email"], config)
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      with :ok <- validate_post_button(op?, attrs, config),
           :ok <- validate_referer(request, config, board),
           :ok <- validate_hidden_input(attrs, config, request, board),
           :ok <- validate_antispam_question(op?, attrs, config, request, board),
           :ok <- validate_captcha(attrs, config, request, board),
           :ok <- validate_dnsbl(request, config),
           :ok <- validate_ban(request, board),
           :ok <- validate_board_lock(config, request, board),
           {:ok, thread} <- fetch_thread(board, thread_param, repo),
           :ok <- validate_thread_lock(thread, request, board),
           {:ok, attrs} <- normalize_post_metadata(attrs, config, request, op?),
           :ok <- Antispam.check_post(board, attrs, request, config, repo: repo),
           :ok <- validate_body(op?, attrs, config),
           :ok <- validate_body_limits(attrs, config),
           :ok <- validate_upload(op?, attrs, config, request),
           :ok <- validate_image_dimensions(attrs, config),
           :ok <- validate_reply_limit(board, thread, config, repo),
           :ok <- validate_image_limit(board, thread, attrs, config, repo),
           :ok <- validate_duplicate_upload(board, thread, attrs, config, repo),
           {:ok, post} <- create_post_record(board, thread, attrs, repo, config, now) do
        _ = maybe_prune_threads(board, config, repo)
        _ = Antispam.log_post(board, attrs, request, repo: repo)
        _ = Build.rebuild_after_post(board, post, config: config, repo: repo)
        {:ok, post, %{noko: noko}}
      end
    end
  end

  @spec update_thread_state(BoardRecord.t(), String.t() | integer(), map(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_thread_state(%BoardRecord{} = board, thread_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, [thread | _]} <- get_thread(board, thread_id, repo: repo),
         {:ok, updated_thread} <-
           thread
           |> Post.thread_state_changeset(attrs)
           |> repo.update() do
      _ = Build.rebuild_thread_state(board, updated_thread.id, config: config, repo: repo)
      {:ok, updated_thread}
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @spec delete_post(BoardRecord.t(), String.t() | integer(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, :post_not_found | :invalid_password | Ecto.Changeset.t()}
  def delete_post(%BoardRecord{} = board, post_id, password, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())
    password = trim_to_nil(password)

    with {:ok, normalized_post_id} <- normalize_thread_id(post_id),
         %Post{} = post <- repo.get_by(Post, id: normalized_post_id, board_id: board.id),
         :ok <- validate_delete_password(post, password),
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
      :error -> {:error, :post_not_found}
      nil -> {:error, :post_not_found}
      {:error, :invalid_password} -> {:error, :invalid_password}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @spec get_post(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found}
  def get_post(%BoardRecord{} = board, post_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, normalized_post_id} <- normalize_thread_id(post_id),
         %Post{} = post <- repo.get_by(Post, id: normalized_post_id, board_id: board.id) do
      {:ok, repo.preload(post, :extra_files)}
    else
      _ -> {:error, :not_found}
    end
  end

  defp maybe_prune_threads(board, config, repo) do
    prune_overflow_threads(board, config, repo)
    prune_early_404_threads(board, config, repo)
    :ok
  end

  defp prune_overflow_threads(board, config, repo) do
    max_threads = max(config.threads_per_page * config.max_pages, 0)

    if max_threads > 0 do
      repo.all(
        from post in Post,
          where: post.board_id == ^board.id and is_nil(post.thread_id),
          order_by: [desc: post.sticky, desc: post.bump_at, desc: post.id],
          offset: ^max_threads,
          select: post.id
      )
      |> Enum.each(fn thread_id ->
        _ = moderate_delete_post(board, thread_id, repo: repo, config: config)
      end)
    end
  end

  defp prune_early_404_threads(board, %{early_404: true} = config, repo) do
    offset = round(config.early_404_page * config.threads_per_page)

    if offset >= 0 do
      reply_counts =
        from(reply in Post,
          where: not is_nil(reply.thread_id),
          group_by: reply.thread_id,
          select: %{thread_id: reply.thread_id, reply_count: count(reply.id)}
        )

      repo.all(
        from thread in Post,
          left_join: counts in subquery(reply_counts),
          on: counts.thread_id == thread.id,
          where: thread.board_id == ^board.id and is_nil(thread.thread_id),
          order_by: [desc: thread.sticky, desc: thread.bump_at, desc: thread.id],
          offset: ^offset,
          select: %{thread_id: thread.id, reply_count: coalesce(counts.reply_count, 0)}
      )
      |> Enum.reduce(
        if(config.early_404_staged, do: {config.early_404_page, 0}, else: {1, 0}),
        fn row, {page, iter} ->
          if row.reply_count < page * config.early_404_replies do
            _ = moderate_delete_post(board, row.thread_id, repo: repo, config: config)
          end

          if config.early_404_staged do
            next_iter = iter + 1

            if next_iter == config.threads_per_page do
              {page + 1, 0}
            else
              {page, next_iter}
            end
          else
            {page, iter}
          end
        end
      )
    end
  end

  defp prune_early_404_threads(_board, _config, _repo), do: :ok

  @spec update_post(BoardRecord.t(), String.t() | integer(), map(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t() | :cite_insert_failed}
  def update_post(%BoardRecord{} = board, post_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())
    attrs = normalize_attrs(attrs)

    with {:ok, post} <- get_post(board, post_id, repo: repo),
         {:ok, attrs} <- normalize_moderation_post_update(post, attrs, config) do
      case repo.transaction(fn ->
             with {:ok, updated_post} <-
                    post
                    |> Post.create_changeset(attrs)
                    |> repo.update(),
                  :ok <- replace_citations(board, updated_post, repo) do
               repo.preload(updated_post, :extra_files)
             else
               {:error, reason} -> repo.rollback(reason)
             end
           end) do
        {:ok, updated_post} ->
          _ = Build.rebuild_after_post_update(board, updated_post, config: config, repo: repo)
          {:ok, updated_post}

        {:error, :not_found} ->
          {:error, :not_found}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec moderate_delete_post(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, :post_not_found | Ecto.Changeset.t()}
  def moderate_delete_post(%BoardRecord{} = board, post_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, normalized_post_id} <- normalize_thread_id(post_id),
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

    with {:ok, post} <- get_post(board, post_id, repo: repo) do
      file_paths = post_delete_file_paths(post, repo)

      case repo.transaction(fn ->
             from(post_file in PostFile, where: post_file.post_id == ^post.id)
             |> repo.delete_all()

             attrs = %{
               file_name: nil,
               file_path: nil,
               thumb_path: nil,
               file_size: nil,
               file_type: nil,
               file_md5: nil,
               image_width: nil,
               image_height: nil,
               spoiler: false
             }

             case post |> Post.create_changeset(attrs) |> repo.update() do
               {:ok, updated_post} -> repo.preload(updated_post, :extra_files, force: true)
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

    with {:ok, post} <- get_post(board, post_id, repo: repo),
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

    with {:ok, post} <- get_post(board, post_id, repo: repo) do
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

  @spec spoilerize_post_file(
          BoardRecord.t(),
          String.t() | integer(),
          non_neg_integer(),
          keyword()
        ) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def spoilerize_post_file(%BoardRecord{} = board, post_id, file_index, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, post} <- get_post(board, post_id, repo: repo),
         {:ok, normalized_index} <- normalize_file_index(file_index),
         {:ok, updated_post, thumb_paths} <-
           spoiler_single_post_file(post, normalized_index, repo) do
      Enum.each(thumb_paths, &Uploads.write_spoiler_thumbnail(&1, config))
      _ = Build.rebuild_after_post_update(board, updated_post, config: config, repo: repo)
      {:ok, updated_post}
    else
      {:error, :invalid_file_index} -> {:error, :not_found}
      other -> other
    end
  end

  @spec move_thread(
          BoardRecord.t(),
          String.t() | integer(),
          BoardRecord.t(),
          keyword()
        ) :: {:ok, Post.t()} | {:error, :not_found | :upload_failed | Ecto.Changeset.t()}
  def move_thread(
        %BoardRecord{} = source_board,
        thread_id,
        %BoardRecord{} = target_board,
        opts \\ []
      ) do
    repo = Keyword.get(opts, :repo, Repo)

    source_config =
      Keyword.get(opts, :source_config, Keyword.get(opts, :config, Config.compose()))

    target_config = Keyword.get(opts, :target_config, source_config)

    with {:ok, [thread | replies]} <- get_thread(source_board, thread_id, repo: repo) do
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

                     with {:ok, updated_post} <-
                            post |> Post.create_changeset(attrs) |> repo.update(),
                          :ok <- move_extra_files(post, source_board, target_board, repo) do
                       {:cont, [updated_post | acc]}
                     else
                       {:error, reason} ->
                         {:halt, repo.rollback(reason)}
                     end
                   end)

                 Enum.each(updated_posts, fn updated_post ->
                   case replace_citations(target_board, updated_post, repo) do
                     :ok -> :ok
                     {:error, reason} -> repo.rollback(reason)
                   end
                 end)

                 Enum.find(updated_posts, &is_nil(&1.thread_id))
               end) do
            {:ok, moved_thread} ->
              _ =
                Build.rebuild_after_delete(
                  source_board,
                  {:thread, thread},
                  config: source_config,
                  repo: repo
                )

              _ =
                Build.rebuild_after_post(target_board, moved_thread,
                  config: target_config,
                  repo: repo
                )

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

  @spec move_reply(
          BoardRecord.t(),
          String.t() | integer(),
          BoardRecord.t(),
          String.t() | integer(),
          keyword()
        ) :: {:ok, Post.t()} | {:error, :not_found | :upload_failed | Ecto.Changeset.t()}
  def move_reply(
        %BoardRecord{} = source_board,
        post_id,
        %BoardRecord{} = target_board,
        target_thread_id,
        opts \\ []
      ) do
    repo = Keyword.get(opts, :repo, Repo)

    source_config =
      Keyword.get(opts, :source_config, Keyword.get(opts, :config, Config.compose()))

    target_config = Keyword.get(opts, :target_config, source_config)

    with {:ok, reply} <- get_post(source_board, post_id, repo: repo),
         false <- is_nil(reply.thread_id),
         {:ok, target_thread} <- fetch_thread(target_board, target_thread_id, repo) do
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

                 with {:ok, updated_reply} <-
                        reply |> Post.create_changeset(attrs) |> repo.update(),
                      :ok <- move_extra_files(reply, source_board, target_board, repo),
                      :ok <- replace_citations(target_board, updated_reply, repo) do
                   updated_reply
                 else
                   {:error, reason} -> repo.rollback(reason)
                 end
               end) do
            {:ok, moved_reply} ->
              _ =
                Build.rebuild_after_delete(
                  source_board,
                  {:reply, reply.thread_id},
                  config: source_config,
                  repo: repo
                )

              _ =
                Build.rebuild_after_post(
                  target_board,
                  moved_reply,
                  config: target_config,
                  repo: repo
                )

              {:ok, repo.preload(moved_reply, :extra_files, force: true)}

            {:error, reason} ->
              _ = reverse_file_moves(file_moves)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      true ->
        {:error, :not_found}

      {:error, :thread_not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec list_threads(BoardRecord.t(), keyword()) :: [Post.t()]
  def list_threads(%BoardRecord{} = board, opts \\ []) do
    config = Keyword.get(opts, :config, Config.compose())
    page = Keyword.get(opts, :page, 1)
    {:ok, page_data} = list_threads_page(board, page, Keyword.put(opts, :config, config))
    Enum.map(page_data.threads, & &1.thread)
  end

  @spec list_recent_posts(keyword()) :: [Post.t()]
  def list_recent_posts(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    limit = Keyword.get(opts, :limit, 25)
    board_ids = Keyword.get(opts, :board_ids)
    search_query = Keyword.get(opts, :query)
    ip_subnet = Keyword.get(opts, :ip_subnet)

    query =
      from post in Post,
        order_by: [desc: post.inserted_at, desc: post.id],
        limit: ^limit

    query =
      case board_ids do
        ids when is_list(ids) -> from post in query, where: post.board_id in ^ids
        _ -> query
      end

    query =
      case trim_to_nil(search_query) do
        nil ->
          query

        term ->
          apply_search_filter(query, term)
      end

    query =
      case trim_to_nil(ip_subnet) do
        nil -> query
        normalized_ip -> from post in query, where: post.ip_subnet == ^normalized_ip
      end

    query
    |> repo.all()
    |> repo.preload(:board)
  end

  @spec list_cites_for_post(Post.t() | integer(), keyword()) :: [Cite.t()]
  def list_cites_for_post(%Post{id: post_id}, opts), do: list_cites_for_post(post_id, opts)

  def list_cites_for_post(post_id, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.all(
      from cite in Cite, where: cite.post_id == ^post_id, order_by: [asc: cite.target_post_id]
    )
  end

  @spec backlinks_map_for_posts([Post.t() | integer()], keyword()) :: %{integer() => [integer()]}
  def backlinks_map_for_posts(posts_or_ids, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    post_ids =
      posts_or_ids
      |> Enum.map(fn
        %Post{id: id} -> id
        id when is_integer(id) -> id
      end)
      |> Enum.uniq()

    if post_ids == [] do
      %{}
    else
      rows =
        repo.all(
          from cite in Cite,
            where: cite.target_post_id in ^post_ids,
            order_by: [asc: cite.post_id],
            select: {cite.target_post_id, cite.post_id}
        )

      Enum.reduce(rows, %{}, fn {target_post_id, post_id}, acc ->
        Map.update(acc, target_post_id, [post_id], fn ids ->
          if post_id in ids, do: ids, else: ids ++ [post_id]
        end)
      end)
    end
  end

  @spec list_nntp_references_for_post(Post.t() | integer(), keyword()) :: [NntpReference.t()]
  def list_nntp_references_for_post(%Post{id: post_id}, opts),
    do: list_nntp_references_for_post(post_id, opts)

  def list_nntp_references_for_post(post_id, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    repo.all(
      from reference in NntpReference,
        where: reference.post_id == ^post_id,
        order_by: [asc: reference.target_post_id]
    )
  end

  @spec list_page_data(BoardRecord.t(), keyword()) :: {:ok, [map()]} | {:error, :not_found}
  def list_page_data(%BoardRecord{} = board, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, first_page} <- list_threads_page(board, 1, config: config, repo: repo) do
      page_data =
        Enum.map(1..first_page.total_pages, fn page ->
          {:ok, data} = list_threads_page(board, page, config: config, repo: repo)
          data
        end)

      {:ok, page_data}
    end
  end

  @spec list_catalog_page(BoardRecord.t(), pos_integer(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def list_catalog_page(%BoardRecord{} = board, page, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    total_threads =
      repo.aggregate(
        from(post in Post, where: post.board_id == ^board.id and is_nil(post.thread_id)),
        :count,
        :id
      )

    page_size =
      if config.catalog_pagination do
        max(config.catalog_threads_per_page, 1)
      else
        max(total_threads, 1)
      end

    total_pages =
      total_threads
      |> Kernel./(page_size)
      |> Float.ceil()
      |> trunc()
      |> max(1)

    if page < 1 or page > total_pages do
      {:error, :not_found}
    else
      offset = (page - 1) * page_size

      threads =
        repo.all(
          from post in Post,
            where: post.board_id == ^board.id and is_nil(post.thread_id),
            order_by: [desc: post.sticky, desc_nulls_last: post.bump_at, desc: post.inserted_at],
            limit: ^page_size,
            offset: ^offset
        )
        |> repo.preload(:extra_files)

      summaries = build_thread_summaries(board, threads, config, repo, include_replies: false)

      {:ok,
       %{
         board: board,
         threads: summaries,
         page: page,
         total_pages: total_pages,
         pages: build_catalog_pages(board, total_pages, config)
       }}
    end
  end

  @spec list_threads_page(BoardRecord.t(), pos_integer(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def list_threads_page(%BoardRecord{} = board, page, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())
    threads_per_page = config.threads_per_page
    max_pages = config.max_pages

    total_threads =
      repo.aggregate(
        from(post in Post, where: post.board_id == ^board.id and is_nil(post.thread_id)),
        :count,
        :id
      )

    total_pages =
      total_threads
      |> Kernel./(threads_per_page)
      |> Float.ceil()
      |> trunc()
      |> max(1)
      |> min(max_pages)

    if page < 1 or page > total_pages do
      {:error, :not_found}
    else
      offset = (page - 1) * threads_per_page

      threads =
        repo.all(
          from post in Post,
            where: post.board_id == ^board.id and is_nil(post.thread_id),
            order_by: [
              desc: post.sticky,
              desc_nulls_last: post.bump_at,
              desc: post.inserted_at,
              desc: post.id
            ],
            limit: ^threads_per_page,
            offset: ^offset
        )
        |> repo.preload(:extra_files)

      summaries = build_thread_summaries(board, threads, config, repo, include_replies: true)
      pages = build_pages(board, total_pages, config)

      {:ok,
       %{
         board: board,
         threads: summaries,
         page: page,
         total_pages: total_pages,
         pages: pages
       }}
    end
  end

  @spec get_thread(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, [Post.t()]} | {:error, :not_found}
  def get_thread(%BoardRecord{} = board, thread_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, normalized_thread_id} <- normalize_thread_id(thread_id),
         %Post{} = thread <-
           repo.one(
             from post in Post,
               where:
                 post.id == ^normalized_thread_id and post.board_id == ^board.id and
                   is_nil(post.thread_id)
           ) do
      replies =
        repo.all(
          from post in Post,
            where: post.board_id == ^board.id and post.thread_id == ^thread.id,
            order_by: [asc: post.inserted_at, asc: post.id]
        )
        |> repo.preload(:extra_files)

      {:ok, [repo.preload(thread, :extra_files) | replies]}
    else
      _ -> {:error, :not_found}
    end
  end

  @spec find_thread_page(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, pos_integer()} | {:error, :not_found}
  def find_thread_page(%BoardRecord{} = board, thread_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, normalized_thread_id} <- normalize_thread_id(thread_id) do
      visible_thread_ids =
        repo.all(
          from post in Post,
            where: post.board_id == ^board.id and is_nil(post.thread_id),
            order_by: [
              desc: post.sticky,
              desc_nulls_last: post.bump_at,
              desc: post.inserted_at,
              desc: post.id
            ],
            limit: ^(config.threads_per_page * config.max_pages),
            select: post.id
        )

      case Enum.find_index(visible_thread_ids, &(&1 == normalized_thread_id)) do
        nil -> {:error, :not_found}
        index -> {:ok, div(index, config.threads_per_page) + 1}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  @spec get_thread_view(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def get_thread_view(%BoardRecord{} = board, thread_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())
    last_posts = normalize_last_posts(Keyword.get(opts, :last_posts), config)

    with {:ok, [thread | replies]} <- get_thread(board, thread_id, repo: repo) do
      reply_image_count = Enum.sum(Enum.map(replies, &post_image_count/1))
      total_reply_count = length(replies)
      has_noko50 = total_reply_count >= config.noko50_min

      shown_replies =
        if(has_noko50, do: maybe_truncate_replies(replies, last_posts), else: replies)

      {:ok,
       %{
         thread: thread,
         replies: shown_replies,
         reply_count: total_reply_count,
         image_count: reply_image_count + post_image_count(thread),
         omitted_posts:
           if(last_posts, do: max(total_reply_count - length(shown_replies), 0), else: 0),
         omitted_images:
           if(last_posts,
             do:
               max(
                 reply_image_count - Enum.sum(Enum.map(shown_replies, &post_image_count/1)),
                 0
               ),
             else: 0
           ),
         last_modified: thread.bump_at || thread.inserted_at,
         has_noko50: has_noko50,
         is_noko50: not is_nil(last_posts) and has_noko50,
         last_count: last_posts || config.noko50_count
       }}
    end
  end

  @spec captcha_required?(map(), boolean()) :: boolean()
  def captcha_required?(config, op?) do
    captcha = Map.get(config, :captcha, %{})

    cond do
      not Map.get(captcha, :enabled, false) -> false
      Map.get(captcha, :mode) == "none" -> false
      Map.get(captcha, :mode) == "op" -> op?
      Map.get(captcha, :mode) == "reply" -> not op?
      true -> true
    end
  end

  defp create_post_record(board, thread, attrs, repo, config, now) do
    upload_entries = Map.get(attrs, "__upload_entries__", [])

    case repo.transaction(fn ->
           with {:ok, post} <- insert_post(board, thread, attrs, repo, config, now),
                {:ok, post} <- maybe_store_uploads(board, post, upload_entries, repo, config),
                :ok <- store_citations(board, post, repo) do
             maybe_bump_thread(thread, attrs, config, repo, now)
             maybe_cycle_thread(board, thread, config, repo)
             post
           else
             {:error, reason} -> repo.rollback(reason)
           end
         end) do
      {:ok, post} -> {:ok, post}
      {:error, reason} -> {:error, reason}
    end
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

  defp insert_post(board, nil, attrs, repo, config, now) do
    attrs =
      attrs
      |> Map.put("board_id", board.id)
      |> Map.put("thread_id", nil)
      |> Map.update("body", "", &(&1 || ""))
      |> Map.put("ip_subnet", request_ip_string(attrs))
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

  defp insert_post(board, thread, attrs, repo, _config, _now) do
    attrs =
      attrs
      |> Map.put("board_id", board.id)
      |> Map.put("thread_id", thread.id)
      |> Map.update("body", "", &(&1 || ""))
      |> Map.put("ip_subnet", request_ip_string(attrs))

    %Post{}
    |> Post.create_changeset(attrs)
    |> repo.insert()
  end

  defp normalize_attrs(attrs) do
    attrs
    |> Enum.into(%{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
    |> normalize_legacy_post_params()
  end

  defp normalize_legacy_post_params(attrs) do
    attrs
    |> put_alias("thread", Map.get(attrs, "resto") || Map.get(attrs, "thread_id"))
    |> put_alias("body", Map.get(attrs, "com") || Map.get(attrs, "message"))
    |> put_alias("subject", Map.get(attrs, "sub") || Map.get(attrs, "topic"))
    |> put_alias("password", Map.get(attrs, "pwd"))
    |> put_alias("g-recaptcha-response", Map.get(attrs, "recaptcha_response_field"))
    |> put_alias("h-captcha-response", Map.get(attrs, "hcaptcha_response"))
    |> maybe_infer_legacy_post_button()
  end

  defp maybe_infer_legacy_post_button(%{"post" => post} = attrs)
       when is_binary(post) and post != "",
       do: attrs

  defp maybe_infer_legacy_post_button(%{"mode" => mode} = attrs) do
    case String.downcase(String.trim(to_string(mode))) do
      "regist" ->
        if is_nil(blank_to_nil(Map.get(attrs, "thread"))) do
          Map.put(attrs, "post", "New Thread")
        else
          Map.put(attrs, "post", "Reply")
        end

      _ ->
        attrs
    end
  end

  defp maybe_infer_legacy_post_button(attrs), do: attrs

  defp put_alias(attrs, _key, nil), do: attrs

  defp put_alias(attrs, key, value) do
    case Map.get(attrs, key) do
      nil -> Map.put(attrs, key, value)
      "" -> Map.put(attrs, key, value)
      _ -> attrs
    end
  end

  defp prepare_uploads(attrs, config) do
    prepare_file_uploads(attrs, config)
  end

  defp prepare_file_uploads(attrs, config) do
    with {:ok, attrs, uploads} <- maybe_add_remote_upload(attrs, config) do
      case Enum.reduce_while(uploads, {:ok, []}, fn upload, {:ok, entries} ->
             case Uploads.describe(upload, config) do
               {:ok, metadata} ->
                 {:cont, {:ok, entries ++ [%{upload: upload, metadata: metadata}]}}

               {:error, reason} ->
                 {:halt, {:error, reason}}
             end
           end) do
        {:ok, []} ->
          {:ok, attrs |> Map.put("file", nil) |> Map.put("__upload_entries__", [])}

        {:ok, [primary | _] = entries} ->
          {:ok,
           attrs
           |> Map.put("file", primary.upload)
           |> Map.put("__upload_metadata__", primary.metadata)
           |> Map.put("__upload_entries__", maybe_apply_spoiler(attrs, entries))}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp normalize_embed(attrs, %{enable_embedding: false}) do
    {:ok, Map.put(attrs, "embed", nil)}
  end

  defp normalize_embed(attrs, config) do
    case trim_to_nil(Map.get(attrs, "embed")) do
      nil ->
        {:ok, Map.put(attrs, "embed", nil)}

      embed ->
        if valid_embed?(embed, config) do
          {:ok, Map.put(attrs, "embed", embed)}
        else
          {:error, :invalid_embed}
        end
    end
  end

  defp valid_embed?(embed, config) do
    Enum.any?(List.wrap(Map.get(config, :embedding, [])), fn rule ->
      case normalize_embedding_rule(rule) do
        {:ok, regex, _html} -> Regex.match?(regex, embed)
        :error -> false
      end
    end)
  end

  defp normalize_embedding_rule([pattern, html]) when is_binary(html),
    do: compile_embedding_regex(pattern, html)

  defp normalize_embedding_rule(%{"pattern" => pattern, "html" => html}),
    do: compile_embedding_regex(pattern, html)

  defp normalize_embedding_rule(%{pattern: pattern, html: html}),
    do: compile_embedding_regex(pattern, html)

  defp normalize_embedding_rule(_rule), do: :error

  defp compile_embedding_regex(%Regex{} = regex, html), do: {:ok, regex, html}

  defp compile_embedding_regex(pattern, html) when is_binary(pattern) and is_binary(html) do
    case parse_regex(pattern) do
      {:ok, regex} -> {:ok, regex, html}
      :error -> :error
    end
  end

  defp compile_embedding_regex(_pattern, _html), do: :error

  defp parse_regex("/" <> rest) do
    with [source, modifiers] <-
           Regex.run(~r{\A/(.*)/([a-z]*)\z}s, "/" <> rest, capture: :all_but_first),
         options <- regex_options(modifiers),
         {:ok, regex} <- Regex.compile(source, options) do
      {:ok, regex}
    else
      _ -> :error
    end
  end

  defp parse_regex(_pattern), do: :error

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

  defp collect_uploads(attrs) do
    numbered_uploads =
      attrs
      |> Enum.filter(fn
        {<<"file", rest::binary>>, %Plug.Upload{}} when rest != "" ->
          String.match?(rest, ~r/^\d+$/)

        _ ->
          false
      end)
      |> Enum.sort_by(fn {key, _upload} ->
        key
        |> String.replace_prefix("file", "")
        |> String.to_integer()
      end)
      |> Enum.map(&elem(&1, 1))

    [
      Map.get(attrs, "file"),
      Map.get(attrs, "files"),
      Map.get(attrs, "files[]") | numbered_uploads
    ]
    |> Enum.flat_map(fn
      nil ->
        []

      %Plug.Upload{} = upload ->
        [upload]

      uploads when is_list(uploads) ->
        Enum.filter(uploads, &match?(%Plug.Upload{}, &1))

      uploads when is_map(uploads) ->
        uploads |> Map.values() |> Enum.filter(&match?(%Plug.Upload{}, &1))

      _ ->
        []
    end)
  end

  defp maybe_add_remote_upload(attrs, config) do
    uploads = collect_uploads(attrs)

    cond do
      uploads != [] ->
        {:ok, attrs, uploads}

      not config.upload_by_url_enabled ->
        {:ok, attrs, uploads}

      true ->
        case trim_to_nil(Map.get(attrs, "file_url") || Map.get(attrs, "url")) do
          nil ->
            {:ok, attrs, uploads}

          remote_url ->
            case Uploads.fetch_remote_upload(remote_url, config) do
              {:ok, upload} -> {:ok, Map.put(attrs, "file", upload), [upload]}
              {:error, reason} -> {:error, reason}
            end
        end
    end
  end

  defp maybe_apply_spoiler(attrs, entries) do
    spoiler? = truthy?(Map.get(attrs, "spoiler"))

    Enum.map(entries, fn entry ->
      %{entry | metadata: Map.put(entry.metadata, :spoiler, spoiler?)}
    end)
  end

  defp truthy?(value) when value in [true, "true", "1", 1, "on"], do: true
  defp truthy?(_value), do: false

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp normalize_post_identity(attrs, config) do
    attrs
    |> Map.update("name", config.anonymous, &default_name(&1, config))
    |> normalize_tripcode()
    |> Map.update("subject", nil, &trim_to_nil/1)
    |> Map.update("password", nil, &trim_to_nil/1)
    |> Map.update("email", nil, &normalize_email/1)
  end

  @spec compat_body(Post.t()) :: String.t()
  def compat_body(%Post{} = post) do
    modifiers =
      []
      |> maybe_append_modifier("flag", join_modifier_values(post.flag_codes))
      |> maybe_append_modifier("flag alt", join_modifier_values(post.flag_alts))
      |> maybe_append_modifier("tag", post.tag)
      |> maybe_append_modifier("proxy", post.proxy)
      |> maybe_append_modifier("trip", post.tripcode)

    Enum.join([post.body || "" | modifiers], "")
  end

  defp normalize_post_metadata(attrs, config, request, op?) do
    attrs =
      attrs
      |> normalize_post_identity(config)
      |> normalize_noko_email()
      |> put_request_ip(request)
      |> normalize_post_text(config)

    with {:ok, attrs} <- normalize_country_flag(attrs, config, request),
         {:ok, attrs} <- normalize_user_flag(attrs, config, request),
         {:ok, attrs} <- normalize_post_tag(attrs, config, op?),
         {:ok, attrs} <- normalize_proxy(attrs, config, request),
         {:ok, attrs} <- normalize_moderator_metadata(attrs, request) do
      {:ok, attrs}
    end
  end

  defp default_name(nil, config), do: config.anonymous

  defp default_name(value, config) do
    case trim_to_nil(value) do
      nil -> config.anonymous
      trimmed -> trimmed
    end
  end

  defp normalize_tripcode(attrs) do
    case trim_to_nil(Map.get(attrs, "name")) do
      nil ->
        Map.put(attrs, "tripcode", nil)

      value ->
        case Regex.run(~r/^(.*?)(##?)(.+)$/u, value) do
          [_, display_name, marker, secret] ->
            trip =
              secret
              |> String.trim()
              |> tripcode_hash(marker == "##")

            attrs
            |> Map.put("name", trim_to_nil(display_name))
            |> Map.put("tripcode", trip)

          _ ->
            Map.put(attrs, "tripcode", nil)
        end
    end
  end

  defp tripcode_hash(secret, secure?) do
    salt = if secure?, do: "secure-trip", else: "trip"

    digest =
      :crypto.hash(:sha, salt <> secret)
      |> Base.encode64(padding: false)
      |> binary_part(0, 10)

    "!" <> digest
  end

  defp trim_to_nil(nil), do: nil

  defp trim_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp body_blank?(nil), do: true

  defp body_blank?(value) when is_binary(value) do
    value
    |> String.replace(~r/\s/u, "")
    |> Kernel.==("")
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(value),
    do: value |> String.trim() |> String.replace(" ", "%20") |> blank_to_nil()

  defp normalize_noko_email(attrs) do
    case String.downcase(attrs["email"] || "") do
      "noko" -> Map.put(attrs, "email", nil)
      "nonoko" -> Map.put(attrs, "email", nil)
      _ -> attrs
    end
  end

  defp normalize_country_flag(attrs, %{country_flags: false}, _request) do
    {:ok, attrs |> Map.put_new("flag_codes", []) |> Map.put_new("flag_alts", [])}
  end

  defp normalize_country_flag(attrs, config, request) do
    if config.allow_no_country and truthy?(Map.get(attrs, "no_country")) do
      {:ok, attrs |> Map.put("flag_codes", []) |> Map.put("flag_alts", [])}
    else
      case resolve_country_flag(config, request, false) do
        nil ->
          {:ok, attrs |> Map.put("flag_codes", []) |> Map.put("flag_alts", [])}

        {code, alt} ->
          {:ok, attrs |> Map.put("flag_codes", [code]) |> Map.put("flag_alts", [alt])}
      end
    end
  end

  defp normalize_user_flag(attrs, %{user_flag: false}, _request) do
    {:ok, attrs |> Map.put_new("flag_codes", []) |> Map.put_new("flag_alts", [])}
  end

  defp normalize_user_flag(attrs, config, request) do
    allowed_flags =
      config.user_flags
      |> Enum.into(%{}, fn {flag, text} ->
        {flag |> to_string() |> String.trim() |> String.downcase(), to_string(text)}
      end)

    default_flag_source = trim_to_nil(config.default_user_flag) || "country"

    default_flags =
      with {:ok, parsed_flags} <-
             parse_user_flags(default_flag_source, config.multiple_flags),
           {:ok, validated_flags} <- validate_user_flags(parsed_flags, allowed_flags, to_string(config.country_flag_fallback.code)) do
        validated_flags
      end

    fallback_flags = [to_string(config.country_flag_fallback.code) |> String.downcase()]

    selected_flags =
      case Map.get(attrs, "user_flag", :missing) do
        :missing ->
          default_flags

        raw_flags when is_binary(raw_flags) ->
          case trim_to_nil(raw_flags) do
            nil ->
              fallback_flags

            trimmed_flags ->
              with {:ok, parsed_flags} <- parse_user_flags(trimmed_flags, config.multiple_flags),
                   {:ok, validated_flags} <- validate_user_flags(parsed_flags, allowed_flags, to_string(config.country_flag_fallback.code)) do
                validated_flags
              end
          end

        _ ->
          default_flags
      end

    case selected_flags do
      {:error, :invalid_user_flag} ->
        {:error, :invalid_user_flag}

      [] ->
        {:ok, attrs |> Map.put_new("flag_codes", []) |> Map.put_new("flag_alts", [])}

      flags when is_list(flags) ->
        existing_pairs =
          Enum.zip(Map.get(attrs, "flag_codes", []), Map.get(attrs, "flag_alts", []))

        resolved_pairs =
          Enum.map(flags, fn flag ->
            resolve_user_flag(flag, allowed_flags, config, request)
          end)

        pairs = unique_flag_pairs(existing_pairs ++ resolved_pairs)

        {:ok,
         attrs
         |> Map.put("flag_codes", Enum.map(pairs, &elem(&1, 0)))
         |> Map.put("flag_alts", Enum.map(pairs, &elem(&1, 1)))}
    end
  end

  defp resolve_user_flag("country", _allowed_flags, config, request) do
    resolve_country_flag(config, request, true)
  end

  defp resolve_user_flag(flag, allowed_flags, config, _request) do
    fallback_code = config.country_flag_fallback.code |> to_string() |> String.downcase()

    if flag == fallback_code do
      normalize_country_metadata(config.country_flag_fallback)
    else
      {flag, Map.fetch!(allowed_flags, flag)}
    end
  end

  defp parse_user_flags(nil, _multiple_flags), do: {:ok, []}

  defp parse_user_flags(raw_flags, true) do
    if String.length(raw_flags) > 300 do
      {:error, :invalid_user_flag}
    else
      {:ok,
       raw_flags
       |> String.split(",", trim: false)
       |> normalize_user_flag_tokens()
       |> unique_flags()}
    end
  end

  defp parse_user_flags(raw_flags, false) do
    {:ok, normalize_user_flag_tokens([raw_flags])}
  end

  defp validate_user_flags(flags, allowed_flags, country_fallback_code) when is_list(flags) do
    if Enum.all?(flags, fn flag ->
         flag == "country" or flag == country_fallback_code or Map.has_key?(allowed_flags, flag)
       end) do
      {:ok, flags}
    else
      {:error, :invalid_user_flag}
    end
  end

  defp normalize_user_flag_tokens(tokens) do
    tokens
    |> Enum.map(&(String.trim(&1) |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
  end

  defp unique_flags(flags) do
    Enum.reduce(flags, [], fn flag, acc ->
      if flag in acc do
        acc
      else
        acc ++ [flag]
      end
    end)
  end

  defp unique_flag_pairs(flag_pairs) do
    Enum.reduce(flag_pairs, [], fn {code, alt}, acc ->
      if Enum.any?(acc, fn {existing_code, _existing_alt} -> existing_code == code end) do
        acc
      else
        acc ++ [{code, alt}]
      end
    end)
  end

  defp resolve_country_flag(config, request, allow_fallback?) do
    case country_metadata(request, config) do
      {code, alt} ->
        {code, alt}

      nil when allow_fallback? ->
        normalize_country_metadata(config.country_flag_fallback)

      nil ->
        nil
    end
  end

  defp request_country_metadata(request) do
    Map.get(request, :country) || Map.get(request, "country") ||
      case {Map.get(request, :country_code) || Map.get(request, "country_code"),
            Map.get(request, :country_name) || Map.get(request, "country_name")} do
        {nil, nil} -> nil
        {code, name} -> %{code: code, name: name}
      end
  end

  defp request_remote_ip(request) do
    case Map.get(request, :remote_ip) || Map.get(request, "remote_ip") do
      nil -> nil
      ip -> normalize_ip(ip)
    end
  end

  defp lookup_country_metadata(nil, _country_flag_data), do: nil

  defp lookup_country_metadata(remote_ip, country_flag_data) when is_map(country_flag_data) do
    Map.get(country_flag_data, remote_ip) || Map.get(country_flag_data, to_string(remote_ip)) ||
      remote_ip
  end

  defp lookup_country_metadata(remote_ip, _country_flag_data), do: remote_ip

  defp country_metadata(request, config) do
    request
    |> request_country_metadata()
    |> case do
      nil ->
        request
        |> request_remote_ip()
        |> lookup_country_metadata(config.country_flag_data)
        |> case do
          %{code: _code, name: _name} = metadata ->
            metadata

          remote_ip ->
            case GeoIp.lookup_country(remote_ip, config) do
              {:ok, metadata} -> metadata
              :error -> nil
            end
        end

      metadata ->
        metadata
    end
    |> normalize_country_metadata()
    |> reject_excluded_country(config.country_flag_exclusions)
  end

  defp normalize_country_metadata(nil), do: nil

  defp normalize_country_metadata(%{code: code, name: name}),
    do: normalize_country_metadata({code, name})

  defp normalize_country_metadata(%{"code" => code, "name" => name}),
    do: normalize_country_metadata({code, name})

  defp normalize_country_metadata([code, name]), do: normalize_country_metadata({code, name})

  defp normalize_country_metadata({code, name}) do
    normalized_code =
      code
      |> to_string()
      |> String.trim()
      |> String.downcase()

    normalized_name =
      name
      |> to_string()
      |> String.trim()

    if normalized_code == "" or normalized_name == "" do
      nil
    else
      {normalized_code, normalized_name}
    end
  end

  defp reject_excluded_country(nil, _excluded_codes), do: nil

  defp reject_excluded_country({code, alt}, excluded_codes) do
    if code in excluded_codes, do: nil, else: {code, alt}
  end

  defp normalize_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp normalize_ip({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp normalize_ip(ip) when is_binary(ip), do: String.trim(ip)

  defp normalize_post_text(attrs, config) do
    attrs
    |> maybe_strip_combining_chars(config)
    |> apply_wordfilters(config)
    |> escape_markup_modifiers()
  end

  defp maybe_strip_combining_chars(attrs, %{strip_combining_chars: true}) do
    Enum.reduce(["name", "email", "subject", "body"], attrs, fn field, acc ->
      Map.update(acc, field, nil, fn
        nil -> nil
        value -> String.replace(value, ~r/\p{M}+/u, "")
      end)
    end)
  end

  defp maybe_strip_combining_chars(attrs, _config), do: attrs

  defp apply_wordfilters(attrs, %{wordfilters: filters}) when is_list(filters) do
    Enum.reduce(filters, attrs, fn filter, acc ->
      case normalize_wordfilter(filter) do
        nil ->
          acc

        {pattern, replacement} ->
          Enum.reduce(["name", "email", "subject", "body"], acc, fn field, field_acc ->
            Map.update(field_acc, field, nil, fn
              nil -> nil
              value -> Regex.replace(pattern, value, replacement)
            end)
          end)
      end
    end)
  end

  defp apply_wordfilters(attrs, _config), do: attrs

  defp normalize_wordfilter({pattern, replacement})
       when is_binary(pattern) and is_binary(replacement) do
    {Regex.compile!(pattern, "u"), replacement}
  end

  defp normalize_wordfilter(%{"pattern" => pattern, "replacement" => replacement})
       when is_binary(pattern) and is_binary(replacement) do
    normalize_wordfilter({pattern, replacement})
  end

  defp normalize_wordfilter(%{pattern: pattern, replacement: replacement})
       when is_binary(pattern) and is_binary(replacement) do
    normalize_wordfilter({pattern, replacement})
  end

  defp normalize_wordfilter(_filter), do: nil

  defp escape_markup_modifiers(attrs) do
    Enum.reduce(["body"], attrs, fn field, acc ->
      Map.update(acc, field, nil, fn
        nil ->
          nil

        value ->
          value
          |> String.replace("<tinyboard", "&lt;tinyboard")
          |> String.replace("</tinyboard>", "&lt;/tinyboard&gt;")
      end)
    end)
  end

  defp normalize_post_tag(attrs, %{allowed_tags: allowed_tags}, true) when is_map(allowed_tags) do
    case Map.get(attrs, "tag") do
      nil ->
        {:ok, Map.put(attrs, "tag", nil)}

      tag ->
        normalized_tag = tag |> to_string() |> String.trim()

        {:ok,
         Map.put(
           attrs,
           "tag",
           if(Map.has_key?(allowed_tags, normalized_tag), do: normalized_tag, else: nil)
         )}
    end
  end

  defp normalize_post_tag(attrs, _config, _op?), do: {:ok, Map.put(attrs, "tag", nil)}

  defp normalize_proxy(attrs, %{proxy_save: true}, request) do
    proxy =
      (request[:forwarded_for] ||
         request["forwarded_for"])
      |> case do
        nil ->
          nil

        value ->
          value
          |> to_string()
          |> sanitize_forwarded_for()
      end

    {:ok, Map.put(attrs, "proxy", proxy)}
  end

  defp normalize_proxy(attrs, _config, _request), do: {:ok, Map.put(attrs, "proxy", nil)}

  defp normalize_moderator_metadata(attrs, request) do
    _ = request
    {:ok, attrs}
  end

  defp request_moderator(request), do: request[:moderator] || request["moderator"]

  defp maybe_append_modifier(modifiers, _name, nil), do: modifiers
  defp maybe_append_modifier(modifiers, _name, ""), do: modifiers

  defp maybe_append_modifier(modifiers, name, value) do
    modifiers ++ ["\n<tinyboard #{name}>#{value}</tinyboard>"]
  end

  defp join_modifier_values(values) when is_list(values), do: Enum.join(values, ",")
  defp join_modifier_values(_values), do: nil

  defp sanitize_forwarded_for(value) do
    ipv4s = Regex.scan(~r/\b(?:\d{1,3}\.){3}\d{1,3}\b/u, value) |> List.flatten()

    ipv6s =
      Regex.scan(~r/\b(?:[0-9a-fA-F]{0,4}:){2,}[0-9a-fA-F:]{0,4}\b/u, value) |> List.flatten()

    (ipv4s ++ ipv6s)
    |> Enum.uniq()
    |> Enum.join(", ")
    |> trim_to_nil()
  end

  defp noko?(email, config) do
    case String.downcase(email || "") do
      "noko" -> true
      "nonoko" -> false
      _ -> config.always_noko
    end
  end

  defp validate_post_button(true, attrs, config) do
    if valid_post_button?(attrs["post"], config.button_newtopic, ["New Topic", "New Thread"]) do
      :ok
    else
      {:error, :invalid_post_mode}
    end
  end

  defp validate_post_button(false, attrs, config) do
    if valid_post_button?(attrs["post"], config.button_reply, ["New Reply", "Reply"]) do
      :ok
    else
      {:error, :invalid_post_mode}
    end
  end

  defp valid_post_button?(value, configured, aliases) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    accepted =
      [configured | aliases]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&(String.trim(&1) |> String.downcase()))

    normalized in accepted
  end

  defp valid_post_button?(_value, _configured, _aliases), do: false

  defp validate_referer(_request, %{referer_match: false}, _board), do: :ok

  defp validate_referer(request, config, board) do
    if moderator_board_access?(request, board) do
      :ok
    else
      referer = request[:referer] || request["referer"]

      if is_binary(referer) and Regex.match?(config.referer_match, URI.decode(referer)) do
        :ok
      else
        {:error, :invalid_referer}
      end
    end
  end

  defp validate_dnsbl(request, config) do
    dnsbl_opts =
      case Map.get(request, :dnsbl_resolver) do
        resolver when is_function(resolver, 1) -> [resolver: resolver]
        _ -> []
      end

    case DNSBL.check(Map.get(request, :remote_ip), config, dnsbl_opts) do
      :ok -> :ok
      {:error, _name} -> {:error, :dnsbl}
    end
  end

  defp validate_board_lock(config, request, board) do
    if config.board_locked and not moderator_board_access?(request, board) do
      {:error, :board_locked}
    else
      :ok
    end
  end

  defp validate_thread_lock(nil, _request, _board), do: :ok

  defp validate_thread_lock(%Post{locked: true}, request, board) do
    if moderator_board_access?(request, board), do: :ok, else: {:error, :thread_locked}
  end

  defp validate_thread_lock(%Post{}, _request, _board), do: :ok

  defp moderator_board_access?(request, board) do
    case request_moderator(request) do
      %ModUser{} = moderator -> Moderation.board_access?(moderator, board)
      _ -> false
    end
  end

  defp store_citations(board, post, repo) do
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

  defp replace_citations(board, post, repo) do
    from(cite in Cite, where: cite.post_id == ^post.id) |> repo.delete_all()
    from(reference in NntpReference, where: reference.post_id == ^post.id) |> repo.delete_all()
    store_citations(board, post, repo)
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

  defp validate_hidden_input(attrs, config, request, board) do
    if moderator_board_access?(request, board) do
      :ok
    else
      hidden_name = to_string(config.hidden_input_name || "hash")

      cond do
        is_nil(config.hidden_input_hash) ->
          :ok

        Map.get(attrs, hidden_name) == config.hidden_input_hash ->
          :ok

        true ->
          {:error, :antispam}
      end
    end
  end

  defp validate_antispam_question(false, _attrs, _config, _request, _board), do: :ok

  defp validate_antispam_question(true, attrs, config, request, board) do
    if moderator_board_access?(request, board) or not is_binary(config.antispam_question) do
      :ok
    else
      answer =
        attrs["antispam_answer"]
        |> to_string()
        |> String.trim()
        |> String.downcase()

      expected =
        config.antispam_question_answer
        |> to_string()
        |> String.trim()
        |> String.downcase()

      if answer != "" and answer == expected, do: :ok, else: {:error, :antispam}
    end
  end

  defp validate_captcha(attrs, config, request, board) do
    op? = is_nil(blank_to_nil(Map.get(attrs, "thread")))

    if moderator_board_access?(request, board) or not captcha_required?(config, op?) do
      :ok
    else
      Captcha.verify(config, attrs, request)
    end
  end

  defp validate_ban(request, board) do
    if moderator_board_access?(request, board) do
      :ok
    else
      if Bans.active_ban_for_request(board, request[:remote_ip] || request["remote_ip"]) do
        {:error, :banned}
      else
        :ok
      end
    end
  end

  defp fetch_thread(_board, nil, _repo), do: {:ok, nil}

  defp fetch_thread(board, thread_param, repo) do
    with {:ok, thread_id} <- normalize_thread_id(thread_param),
         %Post{} = thread <-
           repo.one(
             from post in Post,
               where:
                 post.id == ^thread_id and post.board_id == ^board.id and is_nil(post.thread_id)
           ) do
      {:ok, thread}
    else
      _ -> {:error, :thread_not_found}
    end
  end

  defp validate_body(op?, attrs, config) do
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

  defp validate_body_limits(attrs, config) do
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

  defp validate_upload(op?, attrs, config, request) do
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

  defp validate_image_dimensions(attrs, _config)
       when not is_map_key(attrs, "__upload_entries__"),
       do: :ok

  defp validate_image_dimensions(attrs, config) do
    attrs
    |> Map.get("__upload_entries__", [])
    |> Enum.reduce_while(:ok, fn %{metadata: metadata}, :ok ->
      case validate_image_entry_dimensions(metadata, config) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
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

  defp validate_delete_password(%Post{password: stored_password}, provided_password) do
    if trim_to_nil(stored_password) == provided_password and not is_nil(provided_password) do
      :ok
    else
      {:error, :invalid_password}
    end
  end

  defp validate_reply_limit(_board, nil, _config, _repo), do: :ok

  defp validate_reply_limit(board, thread, config, repo) do
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

  defp validate_image_limit(_board, nil, _attrs, _config, _repo), do: :ok

  defp validate_image_limit(_board, _thread, attrs, _config, _repo)
       when not is_map_key(attrs, "__upload_entries__"),
       do: :ok

  defp validate_image_limit(_board, _thread, %{"__upload_entries__" => []}, _config, _repo),
    do: :ok

  defp validate_image_limit(board, thread, attrs, config, repo) do
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

  defp validate_duplicate_upload(_board, _thread, attrs, _config, _repo)
       when not is_map_key(attrs, "__upload_entries__"),
       do: :ok

  defp validate_duplicate_upload(_board, thread, attrs, config, repo) do
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

  defp maybe_bump_thread(nil, _attrs, _config, _repo, _now), do: :ok

  defp maybe_bump_thread(thread, attrs, config, repo, now) do
    email = String.downcase(attrs["email"] || "")
    should_bump = email != "sage" and not thread.sage and bump_allowed?(thread, config, repo)

    if should_bump do
      repo.update_all(
        from(post in Post, where: post.id == ^thread.id),
        set: [bump_at: now]
      )
    else
      {0, nil}
    end

    :ok
  end

  defp bump_allowed?(thread, config, repo) do
    if config.reply_limit in [0, nil] do
      true
    else
      replies =
        repo.aggregate(from(post in Post, where: post.thread_id == ^thread.id), :count, :id)

      replies + 1 < config.reply_limit
    end
  end

  defp maybe_cycle_thread(_board, nil, _config, _repo), do: :ok

  defp maybe_cycle_thread(_board, thread, config, repo) do
    if thread.cycle and config.cycle_limit not in [0, nil] do
      replies =
        repo.all(
          from post in Post,
            where: post.thread_id == ^thread.id,
            order_by: [desc: post.inserted_at, desc: post.id],
            offset: ^config.cycle_limit,
            select: post.id
        )

      if replies != [] do
        repo.delete_all(from post in Post, where: post.id in ^replies)
      end
    end

    :ok
  end

  defp normalize_thread_id(value), do: ThreadPaths.parse_thread_id(value)

  defp normalize_file_index(file_index) when is_integer(file_index) and file_index >= 0,
    do: {:ok, file_index}

  defp normalize_file_index(file_index) when is_binary(file_index) do
    case Integer.parse(file_index) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, :invalid_file_index}
    end
  end

  defp normalize_file_index(_), do: {:error, :invalid_file_index}

  defp normalize_last_posts(nil, _config), do: nil
  defp normalize_last_posts(false, _config), do: nil
  defp normalize_last_posts(true, config), do: config.noko50_count
  defp normalize_last_posts(value, _config) when is_integer(value) and value > 0, do: value
  defp normalize_last_posts(_value, _config), do: nil

  defp maybe_truncate_replies(replies, nil), do: replies
  defp maybe_truncate_replies(replies, count), do: Enum.take(replies, -count)

  defp build_thread_summaries(_board, [], _config, _repo, _opts), do: []

  defp build_thread_summaries(board, threads, config, repo, opts) do
    include_replies = Keyword.get(opts, :include_replies, true)
    thread_ids = Enum.map(threads, & &1.id)

    reply_stats =
      repo.all(
        from post in Post,
          where: post.board_id == ^board.id and post.thread_id in ^thread_ids,
          group_by: post.thread_id,
          select:
            {post.thread_id, count(post.id), max(post.inserted_at),
             fragment(
               "COALESCE(SUM(CASE WHEN ? LIKE 'image/%' THEN 1 ELSE 0 END), 0)",
               post.file_type
             )}
      )
      |> Map.new(fn {thread_id, reply_count, latest_inserted_at, image_count} ->
        {thread_id,
         %{
           reply_count: reply_count,
           latest_inserted_at: latest_inserted_at,
           image_count: image_count || 0
         }}
      end)

    reply_extra_image_counts =
      repo.all(
        from post_file in PostFile,
          join: post in Post,
          on: post_file.post_id == post.id,
          where:
            post.board_id == ^board.id and post.thread_id in ^thread_ids and
              like(post_file.file_type, "image/%"),
          group_by: post.thread_id,
          select: {post.thread_id, count(post_file.id)}
      )
      |> Map.new()

    replies_by_thread =
      if include_replies do
        preview_count = config.threads_preview

        repo.all(
          from post in Post,
            where: post.board_id == ^board.id and post.thread_id in ^thread_ids,
            order_by: [asc: post.thread_id, desc: post.inserted_at, desc: post.id]
        )
        |> repo.preload(:extra_files)
        |> Enum.group_by(& &1.thread_id)
        |> Map.new(fn {thread_id, replies_desc} ->
          {thread_id, replies_desc |> Enum.take(preview_count) |> Enum.reverse()}
        end)
      else
        %{}
      end

    Enum.map(threads, fn thread ->
      stats =
        Map.get(reply_stats, thread.id, %{
          reply_count: 0,
          latest_inserted_at: nil,
          image_count: 0
        })

      replies = Map.get(replies_by_thread, thread.id, [])
      reply_count = stats.reply_count
      reply_image_count = stats.image_count
      reply_extra_image_count = Map.get(reply_extra_image_counts, thread.id, 0)

      last_modified = stats.latest_inserted_at || thread.inserted_at

      %{
        thread: thread,
        replies: replies,
        reply_count: reply_count,
        image_count: reply_image_count + reply_extra_image_count + post_image_count(thread),
        omitted_posts: max(reply_count - length(replies), 0),
        omitted_images:
          max(
            reply_image_count + reply_extra_image_count -
              Enum.sum(Enum.map(replies, &post_image_count/1)),
            0
          ),
        last_modified: thread.bump_at || last_modified
      }
    end)
  end

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
            {post_file.file_path,
             remap_board_path(post_file.file_path, source_board, target_board)},
            {post_file.thumb_path,
             remap_board_path(post_file.thumb_path, source_board, target_board)}
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

    attrs = %{
      file_name: nil,
      file_path: nil,
      thumb_path: nil,
      file_size: nil,
      file_type: nil,
      file_md5: nil,
      image_width: nil,
      image_height: nil,
      spoiler: false
    }

    case repo.transaction(fn ->
           case post |> Post.create_changeset(attrs) |> repo.update() do
             {:ok, updated_post} -> repo.preload(updated_post, :extra_files, force: true)
             {:error, reason} -> repo.rollback(reason)
           end
         end) do
      {:ok, updated_post} -> {:ok, updated_post, file_paths}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_primary_post_file(%Post{} = post, [promotion | _rest], repo) do
    file_paths = primary_file_delete_paths(post)

    case repo.transaction(fn ->
           with {:ok, _deleted} <- repo.delete(promotion),
                {:ok, promoted_post} <-
                  post
                  |> Post.create_changeset(%{
                    file_name: promotion.file_name,
                    file_path: promotion.file_path,
                    thumb_path: promotion.thumb_path,
                    file_size: promotion.file_size,
                    file_type: promotion.file_type,
                    file_md5: promotion.file_md5,
                    image_width: promotion.image_width,
                    image_height: promotion.image_height,
                    spoiler: promotion.spoiler
                  })
                  |> repo.update() do
             from(post_file in PostFile,
               where: post_file.post_id == ^post.id and post_file.position > 1
             )
             |> repo.update_all(inc: [position: -1])

             repo.preload(promoted_post, :extra_files, force: true)
           else
             {:error, reason} -> repo.rollback(reason)
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
               {:ok, _deleted} = repo.delete(target)

               from(post_file in PostFile,
                 where: post_file.post_id == ^post.id and post_file.position > ^file_index
               )
               |> repo.update_all(inc: [position: -1])

               repo.preload(post, :extra_files, force: true)
             end) do
          {:ok, updated_post} -> {:ok, updated_post, file_paths}
          {:error, reason} -> {:error, reason}
        end
    end
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

  defp path_present?(value) when is_binary(value), do: String.trim(value) != ""
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
    |> Enum.reject(&is_nil/1)
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
    |> Enum.reject(&is_nil/1)
  end

  defp image_count(post), do: if(image_post?(post), do: 1, else: 0)

  defp post_image_count(post) do
    image_count(post) +
      Enum.count(extra_files(post), fn file ->
        is_binary(file.file_type) and String.starts_with?(file.file_type, "image/")
      end)
  end

  defp image_post?(%Post{file_path: file_path, file_type: file_type}) do
    is_binary(file_path) and file_path != "" and is_binary(file_type) and
      String.starts_with?(file_type, "image/")
  end

  defp extra_files(%{extra_files: %Ecto.Association.NotLoaded{}}), do: []
  defp extra_files(%{extra_files: files}) when is_list(files), do: files
  defp extra_files(_post), do: []

  defp cleanup_stored_files(metadata_list) do
    Enum.each(metadata_list, fn metadata ->
      Uploads.remove(Map.get(metadata, :file_path))
      Uploads.remove(Map.get(metadata, :thumb_path))
    end)
  end

  defp build_pages(board, total_pages, config) do
    for num <- 1..total_pages do
      %{
        num: num,
        link:
          if num == 1 do
            "/#{board.uri}"
          else
            "/#{board.uri}/#{String.replace(config.file_page, "%d", Integer.to_string(num))}"
          end
      }
    end
  end

  defp build_catalog_pages(board, total_pages, config) do
    for num <- 1..total_pages do
      %{
        num: num,
        link: Eirinchan.ThreadPaths.catalog_page_path(board, num, config)
      }
    end
  end

  defp maybe_slugify(attrs, config) do
    if config.slugify do
      source = trim_to_nil(attrs["subject"]) || trim_to_nil(attrs["body"]) || ""

      source
      |> String.downcase()
      |> String.replace(~r/<[^>]+>/, "")
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, config.slug_max_size)
      |> case do
        "" -> nil
        slug -> slug
      end
    else
      nil
    end
  end

  defp normalize_moderation_post_update(post, attrs, config) do
    attrs =
      attrs
      |> Map.take(["name", "email", "subject", "body"])
      |> normalize_post_text(config)

    slug =
      if is_nil(post.thread_id) do
        maybe_slugify(
          %{
            "subject" => Map.get(attrs, "subject", post.subject),
            "body" => Map.get(attrs, "body", post.body)
          },
          config
        )
      else
        post.slug
      end

    {:ok, Map.put(attrs, "slug", slug)}
  end

  defp has_primary_file?(%Post{file_path: file_path}) when is_binary(file_path),
    do: file_path != ""

  defp has_primary_file?(_post), do: false

  defp put_request_ip(attrs, request) do
    case Map.get(request, :remote_ip) || Map.get(request, "remote_ip") do
      nil -> attrs
      ip -> Map.put(attrs, "ip_subnet", normalize_request_ip(ip))
    end
  end

  defp request_ip_string(attrs), do: Map.get(attrs, "ip_subnet")

  defp apply_search_filter(query, term) do
    case parse_search_filter(term) do
      {:id, id} ->
        from post in query, where: post.id == ^id

      {:thread, thread_id} ->
        from post in query, where: post.id == ^thread_id or post.thread_id == ^thread_id

      {:subject, value} ->
        apply_field_search(query, :subject, value)

      {:name, value} ->
        apply_field_search(query, :name, value)

      {:generic, value} ->
        apply_generic_search(query, value)
    end
  end

  defp parse_search_filter(term) do
    case Regex.run(~r/^(id|thread|subject|name):(.*)$/u, term, capture: :all_but_first) do
      ["id", id] ->
        case Integer.parse(String.trim(id)) do
          {value, ""} -> {:id, value}
          _ -> {:generic, term}
        end

      ["thread", id] ->
        case Integer.parse(String.trim(id)) do
          {value, ""} -> {:thread, value}
          _ -> {:generic, term}
        end

      ["subject", value] ->
        {:subject, String.trim(value)}

      ["name", value] ->
        {:name, String.trim(value)}

      _ ->
        {:generic, term}
    end
  end

  defp apply_field_search(query, field_name, value) do
    Enum.reduce(search_patterns(value), query, fn pattern, scoped_query ->
      from post in scoped_query, where: ilike(field(post, ^field_name), ^pattern)
    end)
  end

  defp apply_generic_search(query, value) do
    Enum.reduce(search_patterns(value), query, fn pattern, scoped_query ->
      from post in scoped_query,
        where:
          ilike(post.body, ^pattern) or ilike(post.subject, ^pattern) or
            ilike(post.name, ^pattern)
    end)
  end

  defp search_patterns(value) do
    value
    |> tokenize_search_terms()
    |> Enum.map(&wildcard_pattern/1)
  end

  defp tokenize_search_terms(value) do
    matches = Regex.scan(~r/"([^\"]+)"|(\S+)/u, value, capture: :all_but_first)

    terms =
      Enum.map(matches, fn captures ->
        Enum.find(captures, &(&1 not in [nil, ""]))
      end)

    if terms == [] do
      [String.trim(value)]
    else
      Enum.reject(terms, &(&1 == ""))
    end
  end

  defp wildcard_pattern(term) do
    escaped =
      term
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")
      |> String.replace("*", "%")
      |> String.replace("?", "_")

    "%#{escaped}%"
  end

  defp normalize_request_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp normalize_request_ip({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp normalize_request_ip(ip) when is_binary(ip), do: String.trim(ip)
  defp normalize_request_ip(_ip), do: nil
end
