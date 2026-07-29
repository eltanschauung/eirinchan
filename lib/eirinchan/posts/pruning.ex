defmodule Eirinchan.Posts.Pruning do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.GapScore
  alias Eirinchan.Posts.Post

  @spec prune(BoardRecord.t(), map(), module(), function()) :: :ok
  def prune(%BoardRecord{} = board, config, repo, prune_thread_fun)
      when is_function(prune_thread_fun, 1) do
    prune_overflow_threads(board, config, repo, prune_thread_fun)
    prune_early_404_threads(board, config, repo, prune_thread_fun)
    prune_gap_threads(board, config, repo, prune_thread_fun)
    :ok
  end

  def prune(%BoardRecord{} = board, config, repo, prune_thread_fun)
      when is_function(prune_thread_fun, 2) do
    prune_overflow_threads(board, config, repo, prune_thread_fun)
    prune_early_404_threads(board, config, repo, prune_thread_fun)
    prune_gap_threads(board, config, repo, prune_thread_fun)
    :ok
  end

  @spec prune_after_post(BoardRecord.t(), Post.t(), map(), module(), function()) :: :ok
  def prune_after_post(
        %BoardRecord{} = board,
        %Post{thread_id: nil},
        config,
        repo,
        prune_thread_fun
      )
      when is_function(prune_thread_fun, 1) or is_function(prune_thread_fun, 2) do
    prune(board, config, repo, prune_thread_fun)
    :ok
  end

  def prune_after_post(%BoardRecord{}, %Post{}, _config, _repo, _prune_thread_fun), do: :ok

  defp prune_overflow_threads(board, config, repo, prune_thread_fun) do
    max_threads = max(config.threads_per_page * config.max_pages, 0)

    if max_threads > 0 do
      reply_counts = reply_counts_query()

      repo.all(
        from thread in Post,
          left_join: counts in subquery(reply_counts),
          on: counts.thread_id == thread.id,
          where: thread.board_id == ^board.id and is_nil(thread.thread_id),
          order_by: [desc: thread.sticky, desc: thread.bump_at, desc: thread.id],
          offset: ^max_threads,
          select: %{thread_id: thread.id, reply_count: coalesce(counts.reply_count, 0)}
      )
      |> Enum.each(fn row ->
        invoke_prune(prune_thread_fun, row.thread_id, {:overflow, row.reply_count})
      end)
    end
  end

  defp prune_early_404_threads(board, %{early_404: true} = config, repo, prune_thread_fun) do
    offset = round(config.early_404_page * config.threads_per_page)

    if offset >= 0 do
      reply_counts = reply_counts_query()

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
            invoke_prune(prune_thread_fun, row.thread_id, {:early_404, row.reply_count})
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

  defp prune_early_404_threads(_board, _config, _repo, _prune_thread_fun), do: :ok

  defp prune_gap_threads(board, %{early_404_gap: true} = config, repo, prune_thread_fun) do
    reply_metrics =
      from(reply in Post,
        where: not is_nil(reply.thread_id),
        group_by: reply.thread_id,
        select: %{
          thread_id: reply.thread_id,
          reply_count: count(reply.id),
          image_count: filter(count(reply.id), not is_nil(reply.file_path))
        }
      )

    repo.all(
      from thread in Post,
        left_join: metrics in subquery(reply_metrics),
        on: metrics.thread_id == thread.id,
        where: thread.board_id == ^board.id and is_nil(thread.thread_id) and not thread.sticky,
        select: %{
          thread_id: thread.id,
          inserted_at: thread.inserted_at,
          inactive: thread.inactive,
          reply_count: coalesce(metrics.reply_count, 0),
          image_count: coalesce(metrics.image_count, 0)
        }
    )
    |> Enum.each(fn row ->
      if GapScore.eligible?(row.reply_count, config.early_404_gap_max) do
        score = GapScore.calculate(row.inserted_at, row.reply_count, row.image_count)
        warning? = score <= config.early_404_gap_warning
        deletion? = score <= config.early_404_gap_deletion

        if row.inactive != warning? and not deletion? do
          repo.update_all(
            from(post in Post, where: post.id == ^row.thread_id),
            set: [inactive: warning?]
          )
        end

        if deletion? do
          invoke_prune(
            prune_thread_fun,
            row.thread_id,
            {:early_404_gap, score, row.reply_count}
          )
        end
      end
    end)
  end

  defp prune_gap_threads(_board, _config, _repo, _prune_thread_fun), do: :ok

  defp reply_counts_query do
    from(reply in Post,
      where: not is_nil(reply.thread_id),
      group_by: reply.thread_id,
      select: %{thread_id: reply.thread_id, reply_count: count(reply.id)}
    )
  end

  defp invoke_prune(prune_thread_fun, thread_id, reason) do
    case :erlang.fun_info(prune_thread_fun, :arity) do
      {:arity, 2} -> prune_thread_fun.(thread_id, reason)
      _ -> prune_thread_fun.(thread_id)
    end
  end
end
