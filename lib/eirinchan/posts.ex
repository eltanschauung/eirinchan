defmodule Eirinchan.Posts do
  @moduledoc """
  Minimal posting pipeline for OP and reply creation.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Antispam
  alias Eirinchan.Bans
  alias Eirinchan.Build
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Captcha
  alias Eirinchan.DNSBL
  alias Eirinchan.Moderation
  alias Eirinchan.Moderation.ModUser
  alias Eirinchan.Posts.Cite
  alias Eirinchan.Posts.Flags, as: PostsFlags
  alias Eirinchan.Posts.Metadata, as: PostsMetadata
  alias Eirinchan.Posts.Validation, as: PostsValidation
  alias Eirinchan.Posts.Moderation, as: PostsModeration
  alias Eirinchan.Posts.NntpReference
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Posts.Pruning, as: PostsPruning
  alias Eirinchan.Posts.UploadPreparation, as: PostsUploadPreparation
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
             | :too_many_threads
             | :toomanylinks
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

    with {:ok, attrs} <- PostsUploadPreparation.normalize_embed(attrs, config),
         {:ok, attrs} <- PostsUploadPreparation.prepare_uploads(attrs, config) do
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
           :ok <- PostsValidation.validate_body(op?, attrs, config),
           :ok <- PostsValidation.validate_body_limits(attrs, config),
           :ok <- PostsValidation.validate_upload(op?, attrs, config, request),
           :ok <- PostsValidation.validate_image_dimensions(attrs, config),
           :ok <- PostsValidation.validate_reply_limit(board, thread, config, repo),
           :ok <- PostsValidation.validate_image_limit(board, thread, attrs, config, repo),
           :ok <- PostsValidation.validate_duplicate_upload(board, thread, attrs, config, repo),
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
    PostsPruning.prune(board, config, repo, fn thread_id ->
      _ = moderate_delete_post(board, thread_id, repo: repo, config: config)
    end)
  end

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
    PostsModeration.moderate_delete_post(board, post_id, opts)
  end

  @spec moderate_delete_posts_by_ip(BoardRecord.t() | [BoardRecord.t()], String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def moderate_delete_posts_by_ip(board_or_boards, ip_subnet, opts \\ [])

  def moderate_delete_posts_by_ip(%BoardRecord{} = board, ip_subnet, opts) do
    moderate_delete_posts_by_ip([board], ip_subnet, opts)
  end

  def moderate_delete_posts_by_ip(boards, ip_subnet, opts) when is_list(boards) do
    PostsModeration.moderate_delete_posts_by_ip(boards, ip_subnet, opts)
  end

  @spec delete_post_files(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_post_files(%BoardRecord{} = board, post_id, opts \\ []) do
    PostsModeration.delete_post_files(board, post_id, opts)
  end

  @spec delete_post_file(BoardRecord.t(), String.t() | integer(), non_neg_integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_post_file(%BoardRecord{} = board, post_id, file_index, opts \\ []) do
    PostsModeration.delete_post_file(board, post_id, file_index, opts)
  end

  @spec spoilerize_post_files(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def spoilerize_post_files(%BoardRecord{} = board, post_id, opts \\ []) do
    PostsModeration.spoilerize_post_files(board, post_id, opts)
  end

  @spec spoilerize_post_file(
          BoardRecord.t(),
          String.t() | integer(),
          non_neg_integer(),
          keyword()
        ) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def spoilerize_post_file(%BoardRecord{} = board, post_id, file_index, opts \\ []) do
    PostsModeration.spoilerize_post_file(board, post_id, file_index, opts)
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
    PostsModeration.move_thread(source_board, thread_id, target_board, opts)
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
    PostsModeration.move_reply(source_board, post_id, target_board, target_thread_id, opts)
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

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp trim_to_nil(nil), do: nil

  defp trim_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_post_metadata(attrs, config, request, op?) do
    attrs =
      attrs
      |> PostsMetadata.normalize(config, request, op?)
      |> case do
        {:ok, metadata_attrs} -> metadata_attrs
      end
      |> normalize_post_text(config)

    with {:ok, attrs} <- PostsFlags.normalize(attrs, config, request) do
      {:ok, attrs}
    end
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

  defp maybe_append_modifier(modifiers, _name, nil), do: modifiers
  defp maybe_append_modifier(modifiers, _name, ""), do: modifiers

  defp maybe_append_modifier(modifiers, name, value) do
    modifiers ++ ["\n<tinyboard #{name}>#{value}</tinyboard>"]
  end

  defp join_modifier_values(values) when is_list(values), do: Enum.join(values, ",")
  defp join_modifier_values(_values), do: nil

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

  defp request_moderator(request), do: request[:moderator] || request["moderator"]

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

  def replace_citations(board, post, repo) do
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

  defp maybe_bump_thread(nil, _attrs, _config, _repo, _now), do: :ok

  defp maybe_bump_thread(thread, attrs, config, repo, now) do
    email = String.downcase(attrs["email"] || "")
    should_bump = email != "sage" and not thread.sage and bump_allowed?(thread, config, repo)

    if config.anti_bump_flood and not thread.sage do
      bump_at =
        from(post in Post,
          where:
            post.id == ^thread.id or
              (post.thread_id == ^thread.id and
                 fragment("COALESCE(lower(?), '') != 'sage'", post.email)),
          select: max(post.inserted_at)
        )
        |> repo.one()

      repo.update_all(
        from(post in Post, where: post.id == ^thread.id),
        set: [bump_at: bump_at || thread.inserted_at || now]
      )
    else
      if should_bump do
        repo.update_all(
          from(post in Post, where: post.id == ^thread.id),
          set: [bump_at: now]
        )
      else
        {0, nil}
      end
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

  defp validate_delete_password(%Post{password: stored_password}, provided_password) do
    if trim_to_nil(stored_password) == provided_password and not is_nil(provided_password) do
      :ok
    else
      {:error, :invalid_password}
    end
  end
end
