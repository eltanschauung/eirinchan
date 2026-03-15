defmodule Eirinchan.Posts do
  @moduledoc """
  Minimal posting pipeline for OP and reply creation.
  """

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Antispam
  alias Eirinchan.Build
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Cite
  alias Eirinchan.Posts.Flags, as: PostsFlags
  alias Eirinchan.Posts.Metadata, as: PostsMetadata
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Posts.RequestGuards, as: PostsRequestGuards
  alias Eirinchan.Posts.ThreadLookup, as: PostsThreadLookup
  alias Eirinchan.Posts.Validation, as: PostsValidation
  alias Eirinchan.Posts.Moderation, as: PostsModeration
  alias Eirinchan.Posts.NntpReference
  alias Eirinchan.Posts.Post
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Posts.Persistence, as: PostsPersistence
  alias Eirinchan.Posts.Pruning, as: PostsPruning
  alias Eirinchan.Posts.UploadPreparation, as: PostsUploadPreparation
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Uploads

  @spec create_post(BoardRecord.t(), map(), keyword()) ::
          {:ok, Post.t(), map()}
          | {:error,
             :thread_not_found
             | :invalid_post_mode
             | :invalid_referer
             | :invalid_embed
             | :ipaccess
             | :dnsbl
             | :antispam
             | :too_many_threads
             | :toomanylinks
             | :toomanycites
             | :toomanycross
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
             | :mime_exploit
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
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      with :ok <- PostsRequestGuards.validate_post_button(op?, attrs, config),
           :ok <- PostsRequestGuards.validate_referer(request, config, board),
           :ok <- PostsRequestGuards.validate_hidden_input(attrs, config, request, board),
           :ok <-
             PostsRequestGuards.validate_antispam_question(
               op?,
               attrs,
               config,
               request,
               board
             ),
           :ok <- PostsRequestGuards.validate_captcha(attrs, config, request, board, op?),
           :ok <- PostsRequestGuards.validate_ipaccess(attrs, request, config, board),
           :ok <- PostsRequestGuards.validate_dnsbl(attrs, request, config),
           :ok <- PostsRequestGuards.validate_ban(request, board),
           :ok <- PostsRequestGuards.validate_board_lock(config, request, board),
           {:ok, thread} <- PostsThreadLookup.fetch_thread(board, thread_param, repo),
           :ok <- PostsRequestGuards.validate_thread_lock(thread, request, board),
           {:ok, attrs} <- normalize_post_metadata(attrs, config, request, op?),
           :ok <- Antispam.check_post(board, attrs, request, config, repo: repo),
           :ok <- PostsValidation.validate_body(op?, attrs, config),
           :ok <- PostsValidation.validate_body_limits(attrs, config),
           :ok <- PostsValidation.validate_upload(op?, attrs, config, request),
           :ok <- PostsValidation.validate_image_dimensions(attrs, config),
           :ok <- PostsValidation.validate_reply_limit(board, thread, config, repo),
           :ok <- PostsValidation.validate_image_limit(board, thread, attrs, config, repo),
           :ok <- PostsValidation.validate_duplicate_upload(board, thread, attrs, config, repo),
           {:ok, post} <-
             PostsPersistence.create_post_record(board, thread, attrs, repo, config, now, fn ->
               maybe_bump_thread(thread, attrs, config, repo, now)
               maybe_cycle_thread(board, thread, config, repo)
               :ok
             end) do
        _ = maybe_prune_threads(board, config, repo)
        _ = Antispam.log_post(board, attrs, request, repo: repo)
        _ = Build.rebuild_after_post(board, post, config: config, repo: repo)
        {:ok, post, %{noko: false}}
      end
    end
  end

  @spec update_thread_state(BoardRecord.t(), String.t() | integer(), map(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def update_thread_state(%BoardRecord{} = board, thread_id, attrs, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.get(opts, :config, Config.compose())

    with {:ok, [thread | _]} <- PostsThreadLookup.get_thread(board, thread_id, repo: repo),
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

    with {:ok, normalized_post_id} <- PostsThreadLookup.normalize_thread_id(post_id),
         %Post{} = post <- get_post_record(repo, board, normalized_post_id),
         :ok <- validate_delete_password(post, password),
         file_paths <- post_delete_file_paths(post, repo),
         {:ok, _deleted_post} <- repo.delete(post) do
      _ = maybe_recalculate_thread_bump_after_delete(post, config, repo)
      Enum.each(file_paths, &Uploads.remove/1)

      result =
        if is_nil(post.thread_id) do
          _ = Build.rebuild_after_delete(board, {:thread, post}, config: config, repo: repo)
          %{deleted_post_id: PublicIds.public_id(post), thread_id: PublicIds.public_id(post), thread_deleted: true}
        else
          _ =
            Build.rebuild_after_delete(board, {:reply, post.thread_id}, config: config, repo: repo)

          %{deleted_post_id: PublicIds.public_id(post), thread_id: public_thread_id(repo, post), thread_deleted: false}
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

    with {:ok, normalized_post_id} <- PostsThreadLookup.normalize_thread_id(post_id),
         %Post{} = post <- get_post_record(repo, board, normalized_post_id) do
      {:ok, repo.preload(post, :extra_files)}
    else
      _ -> {:error, :not_found}
    end
  end

  @spec get_post_by_internal_id(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, Post.t()} | {:error, :not_found}
  def get_post_by_internal_id(%BoardRecord{} = board, post_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, normalized_post_id} <- PostsThreadLookup.normalize_internal_thread_id(post_id),
         %Post{} = post <- repo.get_by(Post, id: normalized_post_id, board_id: board.id) do
      {:ok, repo.preload(post, :extra_files)}
    else
      _ -> {:error, :not_found}
    end
  end

  def captcha_required?(config, op?) do
    PostsRequestGuards.captcha_required?(config, op?)
  end

  def recalculate_thread_bump(board, thread_id, opts \\ []) do
    if is_nil(thread_id) do
      :ok
    else
      repo = Keyword.get(opts, :repo, Repo)
      config = Keyword.get(opts, :config, Config.compose())

      with %Post{} = thread <-
             repo.one(
               from post in Post,
                 where:
                   post.id == ^thread_id and post.board_id == ^board.id and is_nil(post.thread_id)
             ) do
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
            set: [bump_at: bump_at || thread.inserted_at]
          )
        else
          {0, nil}
        end

        :ok
      else
        _ -> :ok
      end
    end
  end

  defp maybe_prune_threads(board, config, repo) do
    PostsPruning.prune(board, config, repo, fn thread_id ->
      _ =
        case get_post_by_internal_id(board, thread_id, repo: repo) do
          {:ok, thread} -> moderate_delete_post(board, PublicIds.public_id(thread), repo: repo, config: config)
          _ -> :ok
        end
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

  @spec get_thread_by_internal_id(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, [Post.t()]} | {:error, :not_found}
  def get_thread_by_internal_id(%BoardRecord{} = board, thread_id, opts \\ []) do
    PostsThreadLookup.get_thread_by_internal_id(board, thread_id, opts)
  end

  @spec get_thread_view_by_internal_id(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def get_thread_view_by_internal_id(%BoardRecord{} = board, thread_id, opts \\ []) do
    PostsThreadLookup.get_thread_view_by_internal_id(board, thread_id, opts)
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
    |> repo.preload([:board, :thread])
  end

  @spec search_posts(BoardRecord.t(), String.t(), keyword()) ::
          {:ok, [Post.t()]} | {:query_too_broad, [Post.t()]}
  def search_posts(%BoardRecord{} = board, phrase, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    limit = Keyword.get(opts, :limit, 100)
    {query_text, filters} = extract_search_query_parts(phrase)

    if search_query_too_broad?(query_text, filters) do
      {:query_too_broad, []}
    else
      posts =
        from(post in Post,
          where: post.board_id == ^board.id,
          order_by: [desc: post.inserted_at, desc: post.id],
          limit: ^limit
        )
        |> apply_search_text(query_text)
        |> apply_search_filters(filters)
        |> repo.all()
        |> repo.preload([:board, :thread])

      if length(posts) == limit do
        {:query_too_broad, posts}
      else
        {:ok, posts}
      end
    end
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
      visible_posts =
        case Enum.all?(posts_or_ids, &match?(%Post{}, &1)) do
          true -> posts_or_ids
          false ->
            repo.all(
              from post in Post,
                where: post.id in ^post_ids,
                select: %{id: post.id, public_id: post.public_id}
            )
        end

      public_ids_by_internal = Map.new(visible_posts, fn post -> {post.id, PublicIds.public_id(post)} end)

      rows =
        repo.all(
          from cite in Cite,
            where: cite.target_post_id in ^post_ids,
            order_by: [asc: cite.post_id],
            select: {cite.target_post_id, cite.post_id}
        )

      Enum.reduce(rows, %{}, fn {target_post_id, post_id}, acc ->
        case {Map.get(public_ids_by_internal, target_post_id), Map.get(public_ids_by_internal, post_id)} do
          {target_public_id, post_public_id}
          when is_integer(target_public_id) and is_integer(post_public_id) ->
            Map.update(acc, target_public_id, [post_public_id], fn ids ->
              if post_public_id in ids, do: ids, else: ids ++ [post_public_id]
            end)

          _ ->
            acc
        end
      end)
    end
  end

  defp public_thread_id(repo, %Post{thread_id: thread_id}) when is_integer(thread_id) do
    case repo.get(Post, thread_id) do
      %Post{} = thread -> PublicIds.public_id(thread)
      _ -> thread_id
    end
  end

  defp get_post_record(repo, board, normalized_post_id) do
    repo.get_by(Post, public_id: normalized_post_id, board_id: board.id) ||
      repo.get_by(Post, id: normalized_post_id, board_id: board.id)
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
    sort_by = normalize_catalog_sort(Keyword.get(opts, :sort_by, "bump:desc"))
    search_term = normalize_catalog_search(Keyword.get(opts, :search, ""))

    reply_counts_query =
      from post in Post,
        where: post.board_id == ^board.id and not is_nil(post.thread_id),
        group_by: post.thread_id,
        select: %{thread_id: post.thread_id, reply_count: count(post.id)}

    base_query =
      from post in Post,
        where: post.board_id == ^board.id and is_nil(post.thread_id)

    base_query =
      if search_term == "" do
        base_query
      else
        pattern = "%" <> search_term <> "%"

        from post in base_query,
          where:
            ilike(fragment("COALESCE(?, '')", post.subject), ^pattern) or
              ilike(fragment("COALESCE(?, '')", post.body), ^pattern)
      end

    total_threads =
      repo.aggregate(base_query, :count, :id)

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

      thread_query =
        from post in base_query,
          left_join: reply_count in subquery(reply_counts_query),
          on: reply_count.thread_id == post.id

      thread_query =
        thread_query
        |> order_catalog_threads(sort_by)
        |> then(fn query -> from q in query, limit: ^page_size, offset: ^offset end)

      threads =
        repo.all(thread_query)
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

  defp order_catalog_threads(query, "time:desc") do
    from [post, _reply_count] in query,
      order_by: [desc: post.sticky, desc: post.inserted_at, desc: post.id]
  end

  defp order_catalog_threads(query, "reply:desc") do
    from [post, reply_count] in query,
      order_by: [
        desc: post.sticky,
        desc: fragment("COALESCE(?, 0)", reply_count.reply_count),
        desc_nulls_last: post.bump_at,
        desc: post.inserted_at,
        desc: post.id
      ]
  end

  defp order_catalog_threads(query, _sort_by) do
    from [post, _reply_count] in query,
      order_by: [desc: post.sticky, desc_nulls_last: post.bump_at, desc: post.inserted_at, desc: post.id]
  end

  defp normalize_catalog_sort(value) when value in ["bump:desc", "time:desc", "reply:desc"],
    do: value

  defp normalize_catalog_sort(_value), do: "bump:desc"

  defp normalize_catalog_search(value) when is_binary(value), do: String.trim(value)
  defp normalize_catalog_search(_value), do: ""

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
    PostsThreadLookup.get_thread(board, thread_id, opts)
  end

  @spec find_thread_page(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, pos_integer()} | {:error, :not_found}
  def find_thread_page(%BoardRecord{} = board, thread_id, opts \\ []) do
    opts = Keyword.put_new(opts, :config, Config.compose())
    PostsThreadLookup.find_thread_page(board, thread_id, opts)
  end

  @spec get_thread_view(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def get_thread_view(%BoardRecord{} = board, thread_id, opts \\ []) do
    opts = Keyword.put_new(opts, :config, Config.compose())
    PostsThreadLookup.get_thread_view(board, thread_id, opts)
  end

  @spec fetch_thread(BoardRecord.t(), String.t() | integer() | nil, keyword()) ::
          {:ok, Post.t() | nil} | {:error, :thread_not_found}
  def fetch_thread(%BoardRecord{} = board, thread_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    PostsThreadLookup.fetch_thread(board, thread_id, repo)
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

        {:literal, pattern, replacement} ->
          Map.update(acc, "body", nil, fn
            nil -> nil
            value ->
              Regex.replace(Regex.compile!(Regex.escape(pattern), "iu"), value, replacement)
          end)

        {:regex, pattern, replacement} ->
          Map.update(acc, "body", nil, fn
            nil -> nil
            value -> Regex.replace(pattern, value, replacement)
          end)
      end
    end)
  end

  defp apply_wordfilters(attrs, _config), do: attrs

  defp normalize_wordfilter({pattern, replacement})
       when is_binary(pattern) and is_binary(replacement) do
    {:literal, pattern, replacement}
  end

  defp normalize_wordfilter({pattern, replacement, regex?})
       when is_binary(pattern) and is_binary(replacement) do
    if truthy?(regex?) do
      {:regex, Regex.compile!(pattern, "u"), replacement}
    else
      {:literal, pattern, replacement}
    end
  end

  defp normalize_wordfilter([pattern, replacement])
       when is_binary(pattern) and is_binary(replacement) do
    {:literal, pattern, replacement}
  end

  defp normalize_wordfilter([pattern, replacement, regex?])
       when is_binary(pattern) and is_binary(replacement) do
    if truthy?(regex?) do
      {:regex, Regex.compile!(pattern, "u"), replacement}
    else
      {:literal, pattern, replacement}
    end
  end

  defp normalize_wordfilter(%{"pattern" => pattern, "replacement" => replacement} = entry)
       when is_binary(pattern) and is_binary(replacement) do
    if truthy?(Map.get(entry, "regex")) do
      {:regex, Regex.compile!(pattern, "u"), replacement}
    else
      {:literal, pattern, replacement}
    end
  end

  defp normalize_wordfilter(%{pattern: pattern, replacement: replacement} = entry)
       when is_binary(pattern) and is_binary(replacement) do
    if truthy?(Map.get(entry, :regex)) do
      {:regex, Regex.compile!(pattern, "u"), replacement}
    else
      {:literal, pattern, replacement}
    end
  end

  defp normalize_wordfilter(_filter), do: nil

  defp truthy?(value) when value in [true, "true", "1", 1, "yes", "on"], do: true
  defp truthy?(_value), do: false

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

  def replace_citations(board, post, repo) do
    from(cite in Cite, where: cite.post_id == ^post.id) |> repo.delete_all()
    from(reference in NntpReference, where: reference.post_id == ^post.id) |> repo.delete_all()
    PostsPersistence.store_citations(board, post, repo)
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

  defp maybe_recalculate_thread_bump_after_delete(%Post{thread_id: nil}, _config, _repo), do: :ok

  defp maybe_recalculate_thread_bump_after_delete(%Post{board_id: board_id, thread_id: thread_id}, config, repo) do
    if config.anti_bump_flood do
      board = %BoardRecord{id: board_id}
      recalculate_thread_bump(board, thread_id, config: config, repo: repo)
    else
      :ok
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
        repo.all(
          from post in Post,
            where: post.board_id == ^board.id and post.thread_id in ^thread_ids,
            order_by: [asc: post.thread_id, desc: post.inserted_at, desc: post.id]
        )
        |> repo.preload(:extra_files)
        |> Enum.group_by(& &1.thread_id)
        |> Map.new(fn {thread_id, replies_desc} ->
          thread = Enum.find(threads, &(&1.id == thread_id))
          preview_count = thread_preview_count(thread, config)
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
        has_noko50: reply_count >= config.noko50_min,
        last_count: config.noko50_count,
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

  defp thread_preview_count(%Post{sticky: true}, config) do
    sticky_preview = Map.get(config, :threads_preview_sticky, config.threads_preview)

    if is_integer(sticky_preview) and sticky_preview >= 0 do
      sticky_preview
    else
      config.threads_preview
    end
  end

  defp thread_preview_count(_thread, config), do: config.threads_preview

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

  defp extract_search_query_parts(value) do
    pattern = ~r/(^|\s)(\w+):("(.*)?"|[^\s]*)/u

    Regex.scan(pattern, value, capture: :all_but_first)
    |> Enum.reduce({value, %{}}, fn captures, {current, filters} ->
      [prefix, name, raw_value | rest] = captures
      quoted_value = List.first(rest)
      filter_name = String.downcase(name)
      filter_value = if quoted_value not in [nil, ""], do: quoted_value, else: raw_value

      if filter_name in ["id", "thread", "subject", "name"] do
        {
          current
          |> String.replace(prefix <> name <> ":" <> raw_value, prefix, global: false)
          |> String.trim(),
          Map.put(filters, filter_name, String.trim(filter_value))
        }
      else
        {current, filters}
      end
    end)
  end

  defp search_query_too_broad?(query_text, filters) do
    filters == %{} and not Regex.match?(~r/[^*^\s]/u, query_text || "")
  end

  defp apply_search_text(query, nil), do: query
  defp apply_search_text(query, ""), do: query

  defp apply_search_text(query, value) do
    Enum.reduce(search_patterns(value), query, fn pattern, scoped_query ->
      from post in scoped_query, where: ilike(post.body, ^pattern)
    end)
  end

  defp apply_search_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {"id", value}, scoped_query ->
        case Integer.parse(value) do
          {public_id, ""} -> from post in scoped_query, where: post.public_id == ^public_id
          _ -> scoped_query
        end

      {"thread", value}, scoped_query ->
        case Integer.parse(value) do
          {thread_public_id, ""} ->
            from post in scoped_query,
              left_join: thread in Post,
              on: thread.id == coalesce(post.thread_id, post.id),
              where: thread.public_id == ^thread_public_id

          _ ->
            scoped_query
        end

      {"subject", value}, scoped_query ->
        from post in scoped_query,
          where: fragment("lower(coalesce(?, '')) = lower(?)", post.subject, ^value)

      {"name", value}, scoped_query ->
        from post in scoped_query,
          where: fragment("lower(coalesce(?, '')) = lower(?)", post.name, ^value)

      {_unknown, _value}, scoped_query ->
        scoped_query
    end)
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
