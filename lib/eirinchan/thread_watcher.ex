defmodule Eirinchan.ThreadWatcher do
  import Ecto.Query, warn: false

  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.PostOwnership.Ownership
  alias Eirinchan.Posts.Cite
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.ThreadWatcher.Watch

  def list_watches(browser_token) when is_binary(browser_token) do
    Watch
    |> where([watch], watch.browser_token == ^browser_token)
    |> order_by([watch], asc: watch.board_uri, desc: watch.updated_at)
    |> Repo.all()
  end

  def list_watch_summaries(browser_token) when is_binary(browser_token) do
    watches = list_watches(browser_token)

    if watches == [] do
      []
    else
      thread_ids = Enum.map(watches, & &1.thread_id)

      threads =
        from(thread in Post,
          join: board in BoardRecord,
          on: board.id == thread.board_id,
          where: is_nil(thread.thread_id) and thread.id in ^thread_ids,
          select: %{
            thread_id: thread.id,
            board_uri: board.uri,
            board_title: board.title,
            subject: thread.subject,
            body: thread.body,
            slug: thread.slug,
            inserted_at: thread.inserted_at
          }
        )
        |> Repo.all()
        |> Map.new(&{&1.thread_id, &1})

      stats = thread_stats(thread_ids)
      unread = unread_counts(watches, thread_ids)
      you_unread = unread_you_counts(watches, thread_ids, browser_token)

      watches
      |> Enum.map(fn watch ->
        case threads[watch.thread_id] do
          nil ->
            nil

          thread ->
            stat =
              Map.get(stats, watch.thread_id, %{last_post_id: watch.thread_id, post_count: 1})

            %{
              board_uri: watch.board_uri,
              board_title: thread.board_title,
              thread_id: watch.thread_id,
              subject: thread.subject,
              excerpt: excerpt(thread.body),
              slug: thread.slug,
              inserted_at: thread.inserted_at,
              updated_at: watch.updated_at,
              post_count: stat.post_count,
              last_post_id: stat.last_post_id,
              last_seen_post_id: watch.last_seen_post_id || watch.thread_id,
              unread_count: Map.get(unread, {watch.board_uri, watch.thread_id}, 0),
              you_unread_count: Map.get(you_unread, {watch.board_uri, watch.thread_id}, 0)
            }
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(
        fn summary -> {summary.unread_count > 0, summary.updated_at, summary.last_post_id} end,
        :desc
      )
    end
  end

  def current_last_post_id(board_uri, thread_id)
      when is_binary(board_uri) and is_integer(thread_id) do
    from(post in Post,
      where:
        post.board_id in subquery(
          from(board in BoardRecord, where: board.uri == ^board_uri, select: board.id)
        ),
      where: post.id == ^thread_id or post.thread_id == ^thread_id,
      select: max(post.id)
    )
    |> Repo.one()
    |> Kernel.||(thread_id)
  end

  def watched_thread_ids(browser_token, board_uri)
      when is_binary(browser_token) and is_binary(board_uri) do
    Watch
    |> where([watch], watch.browser_token == ^browser_token and watch.board_uri == ^board_uri)
    |> select([watch], watch.thread_id)
    |> Repo.all()
    |> MapSet.new()
  end

  def watch_state_for_board(browser_token, board_uri)
      when is_binary(browser_token) and is_binary(board_uri) do
    watches =
      Watch
      |> where([watch], watch.browser_token == ^browser_token and watch.board_uri == ^board_uri)
      |> Repo.all()

    if watches == [] do
      %{}
    else
      thread_ids = Enum.map(watches, & &1.thread_id)
      unread = unread_counts(watches, thread_ids)
      you_unread = unread_you_counts(watches, thread_ids, browser_token)

      watches
      |> Enum.map(fn watch ->
        unread_count = Map.get(unread, {watch.board_uri, watch.thread_id}, 0)
        you_unread_count = Map.get(you_unread, {watch.board_uri, watch.thread_id}, 0)

        {watch.thread_id,
         %{
           watched: true,
           unread_count: unread_count,
           you_unread_count: you_unread_count,
           last_seen_post_id: watch.last_seen_post_id || watch.thread_id
         }}
      end)
      |> Map.new()
    end
  end

  def watch_count(browser_token) when is_binary(browser_token) do
    Watch
    |> where([watch], watch.browser_token == ^browser_token)
    |> select([watch], count(watch.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  def watch_metrics(browser_token) when is_binary(browser_token) do
    watches = list_watches(browser_token)

    if watches == [] do
      %{watcher_count: 0, watcher_you_count: 0}
    else
      thread_ids = Enum.map(watches, & &1.thread_id)

      watcher_you_count =
        unread_you_counts(watches, thread_ids, browser_token)
        |> Map.values()
        |> Enum.sum()

      %{watcher_count: length(watches), watcher_you_count: watcher_you_count}
    end
  end

  def watched?(browser_token, board_uri, thread_id)
      when is_binary(browser_token) and is_binary(board_uri) and is_integer(thread_id) do
    Repo.exists?(
      from watch in Watch,
        where:
          watch.browser_token == ^browser_token and watch.board_uri == ^board_uri and
            watch.thread_id == ^thread_id
    )
  end

  def watch_thread(browser_token, board_uri, thread_id, attrs \\ %{})
      when is_binary(browser_token) and is_binary(board_uri) and is_integer(thread_id) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:browser_token, browser_token)
      |> Map.put(:board_uri, board_uri)
      |> Map.put(:thread_id, thread_id)

    %Watch{}
    |> Watch.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [updated_at: DateTime.utc_now(), last_seen_post_id: attrs[:last_seen_post_id]]
      ],
      conflict_target: [:browser_token, :board_uri, :thread_id]
    )
  end

  def unwatch_thread(browser_token, board_uri, thread_id)
      when is_binary(browser_token) and is_binary(board_uri) and is_integer(thread_id) do
    {count, _} =
      Repo.delete_all(
        from watch in Watch,
          where:
            watch.browser_token == ^browser_token and watch.board_uri == ^board_uri and
              watch.thread_id == ^thread_id
      )

    {:ok, count}
  end

  def mark_seen(browser_token, board_uri, thread_id, last_seen_post_id)
      when is_binary(browser_token) and is_binary(board_uri) and is_integer(thread_id) and
             is_integer(last_seen_post_id) do
    case Repo.get_by(Watch,
           browser_token: browser_token,
           board_uri: board_uri,
           thread_id: thread_id
         ) do
      nil ->
        {:ok, nil}

      watch ->
        watch
        |> Watch.changeset(%{last_seen_post_id: last_seen_post_id})
        |> Repo.update()
    end
  end

  defp thread_stats(thread_ids) do
    from(post in Post,
      where: post.id in ^thread_ids or post.thread_id in ^thread_ids,
      group_by: fragment("COALESCE(?, ?)", post.thread_id, post.id),
      select: {
        fragment("COALESCE(?, ?)", post.thread_id, post.id),
        %{last_post_id: max(post.id), post_count: count(post.id)}
      }
    )
    |> Repo.all()
    |> Map.new()
  end

  defp unread_counts(watches, thread_ids) do
    min_seen =
      watches
      |> Enum.map(fn watch -> watch.last_seen_post_id || watch.thread_id end)
      |> Enum.min()

    posts =
      from(post in Post,
        where: post.id in ^thread_ids or post.thread_id in ^thread_ids,
        where: post.id > ^min_seen,
        select: {fragment("COALESCE(?, ?)", post.thread_id, post.id), post.id}
      )
      |> Repo.all()
      |> Enum.group_by(fn {thread_id, _post_id} -> thread_id end, fn {_thread_id, post_id} ->
        post_id
      end)

    watches
    |> Enum.map(fn watch ->
      seen = watch.last_seen_post_id || watch.thread_id
      count = posts |> Map.get(watch.thread_id, []) |> Enum.count(&(&1 > seen))
      {{watch.board_uri, watch.thread_id}, count}
    end)
    |> Map.new()
  end

  defp unread_you_counts(watches, thread_ids, browser_token) do
    min_seen =
      watches
      |> Enum.map(fn watch -> watch.last_seen_post_id || watch.thread_id end)
      |> Enum.min()

    posts =
      from(post in Post,
        join: cite in Cite,
        on: cite.post_id == post.id,
        join: ownership in Ownership,
        on:
          ownership.post_id == cite.target_post_id and ownership.browser_token == ^browser_token,
        where: post.id in ^thread_ids or post.thread_id in ^thread_ids,
        where: post.id > ^min_seen,
        distinct: post.id,
        select: {fragment("COALESCE(?, ?)", post.thread_id, post.id), post.id}
      )
      |> Repo.all()
      |> Enum.group_by(fn {thread_id, _post_id} -> thread_id end, fn {_thread_id, post_id} ->
        post_id
      end)

    watches
    |> Enum.map(fn watch ->
      seen = watch.last_seen_post_id || watch.thread_id
      count = posts |> Map.get(watch.thread_id, []) |> Enum.count(&(&1 > seen))
      {{watch.board_uri, watch.thread_id}, count}
    end)
    |> Map.new()
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
