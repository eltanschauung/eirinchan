defmodule Eirinchan.Posts.Pruning do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post

  @spec prune(BoardRecord.t(), map(), module(), (integer() -> any())) :: :ok
  def prune(%BoardRecord{} = board, config, repo, delete_thread_fun) when is_function(delete_thread_fun, 1) do
    prune_overflow_threads(board, config, repo, delete_thread_fun)
    prune_early_404_threads(board, config, repo, delete_thread_fun)
    :ok
  end

  defp prune_overflow_threads(board, config, repo, delete_thread_fun) do
    max_threads = max(config.threads_per_page * config.max_pages, 0)

    if max_threads > 0 do
      repo.all(
        from post in Post,
          where: post.board_id == ^board.id and is_nil(post.thread_id),
          order_by: [desc: post.sticky, desc: post.bump_at, desc: post.id],
          offset: ^max_threads,
          select: post.id
      )
      |> Enum.each(delete_thread_fun)
    end
  end

  defp prune_early_404_threads(board, %{early_404: true} = config, repo, delete_thread_fun) do
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
            delete_thread_fun.(row.thread_id)
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

  defp prune_early_404_threads(_board, _config, _repo, _delete_thread_fun), do: :ok
end
