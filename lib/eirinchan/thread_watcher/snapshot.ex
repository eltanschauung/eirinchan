defmodule Eirinchan.ThreadWatcher.Snapshot do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.PostOwnership.Ownership
  alias Eirinchan.Posts.Cite
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.ThreadWatcher.Watch

  @empty_metrics %{watcher_count: 0, watcher_unread_count: 0, watcher_you_count: 0}
  @empty_snapshot %{
    metrics: @empty_metrics,
    watch_state_by_board: %{},
    summaries: []
  }

  def empty, do: @empty_snapshot

  def build(browser_identity, opts \\ []) when is_binary(browser_identity) do
    repo = Keyword.get(opts, :repo, Repo)
    browser_ref = BrowserIdentity.reference(browser_identity)
    rows = load_watch_rows(repo, browser_ref)

    if rows == [] do
      @empty_snapshot
    else
      you_by_watch = load_you_stats(repo, browser_ref, rows)
      rows = Enum.map(rows, &attach_you_stats(&1, you_by_watch))

      %{
        metrics: metrics(rows),
        watch_state_by_board: watch_state_by_board(rows),
        summaries: maybe_summaries(repo, rows, Keyword.get(opts, :summaries, false))
      }
    end
  end

  # Keep the common page-read query deliberately narrow. Subject/body and the
  # other summary-only columns are loaded only for the dedicated watcher view.
  defp load_watch_rows(repo, browser_ref) do
    from(watch in Watch,
      join: thread in Post,
      on: thread.id == watch.thread_id and is_nil(thread.thread_id),
      join: board in BoardRecord,
      on: board.id == thread.board_id,
      left_join: seen_post in Post,
      on:
        seen_post.board_id == thread.board_id and seen_post.id == watch.last_seen_post_id and
          (seen_post.id == thread.id or seen_post.thread_id == thread.id),
      left_join: unread_post in Post,
      on:
        unread_post.board_id == thread.board_id and unread_post.thread_id == thread.id and
          unread_post.id > fragment("COALESCE(?, ?)", watch.last_seen_post_id, thread.id),
      where: watch.browser_ref == ^browser_ref and watch.activated,
      group_by: [
        watch.id,
        watch.last_seen_post_id,
        watch.updated_at,
        thread.id,
        thread.public_id,
        board.uri,
        seen_post.public_id
      ],
      order_by: [asc: board.uri, desc: watch.updated_at],
      select: %{
        watch_id: watch.id,
        board_uri: board.uri,
        thread_internal_id: thread.id,
        thread_public_id: thread.public_id,
        updated_at: watch.updated_at,
        last_seen_public_id: fragment("COALESCE(?, ?)", seen_post.public_id, thread.public_id),
        unread_count: count(unread_post.id)
      }
    )
    |> repo.all()
  end

  defp load_you_stats(repo, browser_ref, rows) when is_list(rows) do
    if Enum.all?(rows, &(&1.unread_count == 0)) do
      %{}
    else
      do_load_you_stats(repo, browser_ref)
    end
  end

  defp do_load_you_stats(repo, browser_ref) do
    from(watch in Watch,
      join: thread in Post,
      on: thread.id == watch.thread_id and is_nil(thread.thread_id),
      join: post in Post,
      on:
        post.board_id == thread.board_id and post.thread_id == thread.id and
          post.id > fragment("COALESCE(?, ?)", watch.last_seen_post_id, thread.id),
      join: cite in Cite,
      on: cite.post_id == post.id,
      join: ownership in Ownership,
      on: ownership.post_id == cite.target_post_id and ownership.browser_ref == ^browser_ref,
      where: watch.browser_ref == ^browser_ref,
      group_by: watch.id,
      select: {watch.id, count(post.id, :distinct), max(post.public_id)}
    )
    |> repo.all()
    |> Map.new(fn {watch_id, count, target_public_id} ->
      {watch_id, %{count: count, target_public_id: target_public_id}}
    end)
  end

  defp attach_you_stats(row, you_by_watch) do
    stats = Map.get(you_by_watch, row.watch_id, %{count: 0, target_public_id: nil})

    row
    |> Map.put(:you_unread_count, stats.count)
    |> Map.put(:you_unread_post_id, stats.target_public_id)
  end

  defp metrics(rows) do
    Enum.reduce(rows, @empty_metrics, fn row, acc ->
      %{
        watcher_count: acc.watcher_count + 1,
        watcher_unread_count: acc.watcher_unread_count + row.unread_count,
        watcher_you_count: acc.watcher_you_count + row.you_unread_count
      }
    end)
  end

  defp watch_state_by_board(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      state = %{
        watched: true,
        unread_count: row.unread_count,
        you_unread_count: row.you_unread_count,
        last_seen_post_id: row.last_seen_public_id
      }

      Map.update(acc, row.board_uri, %{row.thread_public_id => state}, fn board_state ->
        Map.put(board_state, row.thread_public_id, state)
      end)
    end)
  end

  defp maybe_summaries(_repo, _rows, false), do: []

  defp maybe_summaries(repo, rows, true) do
    details_by_thread = load_summary_details(repo, rows)

    rows
    |> Enum.flat_map(fn row ->
      case Map.get(details_by_thread, row.thread_internal_id) do
        nil -> []
        details -> [build_summary(row, details)]
      end
    end)
    |> Enum.sort_by(
      fn summary -> {summary.unread_count > 0, summary.updated_at, summary.last_post_id} end,
      :desc
    )
  end

  defp load_summary_details(repo, rows) do
    thread_ids = Enum.map(rows, & &1.thread_internal_id)

    from(thread in Post,
      join: board in BoardRecord,
      on: board.id == thread.board_id,
      left_join: post in Post,
      on:
        post.board_id == thread.board_id and
          (post.id == thread.id or post.thread_id == thread.id),
      where: thread.id in ^thread_ids and is_nil(thread.thread_id),
      group_by: [
        thread.id,
        thread.subject,
        thread.body,
        thread.slug,
        thread.inserted_at,
        thread.cached_reply_count,
        board.title
      ],
      select: {
        thread.id,
        %{
          board_title: board.title,
          subject: thread.subject,
          body: thread.body,
          slug: thread.slug,
          inserted_at: thread.inserted_at,
          post_count: fragment("COALESCE(?, 0) + 1", thread.cached_reply_count),
          last_post_id: max(post.public_id)
        }
      }
    )
    |> repo.all()
    |> Map.new()
  end

  defp build_summary(row, details) do
    %{
      board_uri: row.board_uri,
      board_title: details.board_title,
      thread_id: row.thread_public_id,
      subject: details.subject,
      excerpt: excerpt(details.body),
      slug: details.slug,
      inserted_at: details.inserted_at,
      updated_at: row.updated_at,
      post_count: details.post_count,
      last_post_id: details.last_post_id || row.thread_public_id,
      last_seen_post_id: row.last_seen_public_id,
      unread_count: row.unread_count,
      you_unread_count: row.you_unread_count,
      you_unread_post_id: row.you_unread_post_id
    }
  end

  defp excerpt(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> nil
      value -> if String.length(value) > 80, do: String.slice(value, 0, 77) <> "...", else: value
    end
  end

  defp excerpt(_), do: nil
end
