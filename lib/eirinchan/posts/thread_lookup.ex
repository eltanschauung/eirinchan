defmodule Eirinchan.Posts.ThreadLookup do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.ThreadPaths

  @spec get_thread(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, [Post.t()]} | {:error, :not_found}
  def get_thread(%BoardRecord{} = board, thread_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, normalized_thread_id} <- normalize_thread_id(thread_id),
         %Post{} = thread <- fetch_thread_record(repo, board, normalized_thread_id) do
      {:ok, load_thread_posts(board, thread, repo)}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_thread_by_internal_id(%BoardRecord{} = board, thread_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, normalized_thread_id} <- normalize_internal_thread_id(thread_id),
         %Post{} = thread <-
           repo.one(
             from post in Post,
               where:
                 post.id == ^normalized_thread_id and post.board_id == ^board.id and
                   is_nil(post.thread_id)
           ) do
      {:ok, load_thread_posts(board, thread, repo)}
    else
      _ -> {:error, :not_found}
    end
  end

  @spec find_thread_page(BoardRecord.t(), String.t() | integer(), keyword()) ::
          {:ok, pos_integer()} | {:error, :not_found}
  def find_thread_page(%BoardRecord{} = board, thread_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.fetch!(opts, :config)

    with {:ok, %Post{} = thread} <- fetch_thread(board, thread_id, repo) do
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
            select: post.public_id
        )

      case Enum.find_index(visible_thread_ids, &(&1 == thread.public_id)) do
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
    config = Keyword.fetch!(opts, :config)
    last_posts = normalize_last_posts(Keyword.get(opts, :last_posts), config)

    with {:ok, [thread | replies]} <- get_thread(board, thread_id, repo: repo) do
      build_thread_view(thread, replies, config, last_posts)
    end
  end

  def get_thread_view_by_internal_id(%BoardRecord{} = board, thread_id, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    config = Keyword.fetch!(opts, :config)
    last_posts = normalize_last_posts(Keyword.get(opts, :last_posts), config)

    with {:ok, [thread | replies]} <- get_thread_by_internal_id(board, thread_id, repo: repo) do
      build_thread_view(thread, replies, config, last_posts)
    end
  end

  defp build_thread_view(thread, replies, config, last_posts) do
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

  @spec fetch_thread(BoardRecord.t(), String.t() | integer() | nil, module()) ::
          {:ok, Post.t() | nil} | {:error, :thread_not_found}
  def fetch_thread(_board, nil, _repo), do: {:ok, nil}

  def fetch_thread(board, thread_param, repo) do
    with {:ok, thread_id} <- normalize_thread_id(thread_param),
         %Post{} = thread <- fetch_thread_record(repo, board, thread_id) do
      {:ok, thread}
    else
      _ -> {:error, :thread_not_found}
    end
  end

  def fetch_thread_by_internal_id(_board, nil, _repo), do: {:ok, nil}

  def fetch_thread_by_internal_id(board, thread_param, repo) do
    with {:ok, thread_id} <- normalize_internal_thread_id(thread_param),
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

  @spec normalize_thread_id(term()) :: {:ok, integer()} | :error
  def normalize_thread_id(value), do: ThreadPaths.parse_thread_id(value)

  def normalize_internal_thread_id(value), do: ThreadPaths.parse_thread_id(value)

  defp normalize_last_posts(nil, _config), do: nil
  defp normalize_last_posts(false, _config), do: nil
  defp normalize_last_posts(true, config), do: config.noko50_count
  defp normalize_last_posts(value, _config) when is_integer(value) and value > 0, do: value
  defp normalize_last_posts(_value, _config), do: nil

  defp maybe_truncate_replies(replies, nil), do: replies
  defp maybe_truncate_replies(replies, count), do: Enum.take(replies, -count)

  defp fetch_thread_record(repo, board, normalized_thread_id) do
    repo.one(
      from post in Post,
        where:
          post.public_id == ^normalized_thread_id and post.board_id == ^board.id and
            is_nil(post.thread_id)
    ) ||
      repo.one(
        from post in Post,
          where:
            post.id == ^normalized_thread_id and post.board_id == ^board.id and
              is_nil(post.thread_id)
      )
  end

  defp load_thread_posts(board, %Post{} = thread, repo) do
    replies =
      repo.all(
        from post in Post,
          where: post.board_id == ^board.id and post.thread_id == ^thread.id,
          order_by: [asc: post.inserted_at, asc: post.id]
      )
      |> repo.preload(:extra_files)

    [repo.preload(thread, :extra_files) | replies]
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
end
