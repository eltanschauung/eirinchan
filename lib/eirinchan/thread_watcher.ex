defmodule Eirinchan.ThreadWatcher do
  import Ecto.Query, warn: false

  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.ThreadWatcher.Snapshot
  alias Eirinchan.ThreadWatcher.Watch

  def snapshot(browser_token, opts \\ []) when is_binary(browser_token) do
    Snapshot.build(browser_token, opts)
  end

  def empty_snapshot, do: Snapshot.empty()

  def list_watches(browser_token) when is_binary(browser_token) do
    browser_token = BrowserIdentity.reference(browser_token)

    from(watch in Watch,
      join: thread in Post,
      on: thread.id == watch.thread_id and is_nil(thread.thread_id),
      join: board in BoardRecord,
      on: board.id == thread.board_id,
      where: watch.browser_token == ^browser_token,
      order_by: [asc: board.uri, desc: watch.updated_at],
      select: {watch, board.uri}
    )
    |> Repo.all()
    |> Enum.map(fn {watch, board_uri} -> %{watch | board_uri: board_uri} end)
  end

  def list_watch_summaries(browser_token) when is_binary(browser_token) do
    browser_token
    |> snapshot(summaries: true)
    |> Map.fetch!(:summaries)
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
    browser_token = BrowserIdentity.reference(browser_token)

    from(watch in Watch,
      join: thread in Post,
      on: thread.id == watch.thread_id and is_nil(thread.thread_id),
      join: board in BoardRecord,
      on: board.id == thread.board_id,
      where: watch.browser_token == ^browser_token and board.uri == ^board_uri,
      select: watch.thread_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def watch_state_for_board(browser_token, board_uri)
      when is_binary(browser_token) and is_binary(board_uri) do
    browser_token
    |> snapshot()
    |> Map.fetch!(:watch_state_by_board)
    |> Map.get(board_uri, %{})
  end

  def watch_count(browser_token) when is_binary(browser_token) do
    browser_token
    |> watch_metrics()
    |> Map.fetch!(:watcher_count)
  end

  def watch_metrics(browser_token) when is_binary(browser_token) do
    browser_token
    |> snapshot()
    |> Map.fetch!(:metrics)
  end

  def watched?(browser_token, board_uri, thread_id)
      when is_binary(browser_token) and is_binary(board_uri) and is_integer(thread_id) do
    browser_token = BrowserIdentity.reference(browser_token)

    Repo.exists?(
      from watch in Watch,
        join: thread in Post,
        on: thread.id == watch.thread_id and is_nil(thread.thread_id),
        join: board in BoardRecord,
        on: board.id == thread.board_id,
        where:
          watch.browser_token == ^browser_token and board.uri == ^board_uri and
            watch.thread_id == ^thread_id
    )
  end

  def watch_thread(browser_token, board_uri, thread_id, attrs \\ %{})
      when is_binary(browser_token) and is_binary(board_uri) and is_integer(thread_id) do
    browser_token = BrowserIdentity.reference(browser_token)
    attrs = Map.new(attrs)

    last_seen_post_id =
      Map.get(attrs, :last_seen_post_id, Map.get(attrs, "last_seen_post_id"))

    insert_attrs =
      attrs
      |> Map.drop([:last_seen_post_id, "last_seen_post_id"])
      |> Map.put(:browser_token, browser_token)
      |> Map.put(:board_uri, board_uri)
      |> Map.put(:thread_id, thread_id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      case %Watch{}
           |> Watch.changeset(insert_attrs)
           |> Repo.insert(
             on_conflict: [set: [board_uri: board_uri, updated_at: now]],
             conflict_target: [:browser_token, :thread_id]
           ) do
        {:ok, proposed_watch} ->
          if proposed_watch.activated do
            from(watch in Watch,
              where: watch.browser_token == ^browser_token and watch.thread_id == ^thread_id
            )
            |> Repo.update_all(set: [activated: true, updated_at: now])
          end

          case last_seen_post_id do
            value when is_integer(value) ->
              case mark_seen(browser_token, board_uri, thread_id, value) do
                {:ok, %Watch{} = watch} -> watch
                {:ok, nil} -> Repo.rollback(:invalid_last_seen_post)
              end

            _ ->
              Repo.get_by!(Watch, browser_token: browser_token, thread_id: thread_id)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def activate_for_reply(thread_id, excluded_browser_token \\ nil)
      when is_integer(thread_id) and
             (is_binary(excluded_browser_token) or is_nil(excluded_browser_token)) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query =
      from(watch in Watch,
        where: watch.thread_id == ^thread_id and not watch.activated
      )

    query =
      if is_binary(excluded_browser_token) do
        excluded_browser_ref = BrowserIdentity.reference(excluded_browser_token)
        from(watch in query, where: watch.browser_token != ^excluded_browser_ref)
      else
        query
      end

    {count, _} = Repo.update_all(query, set: [activated: true, updated_at: now])
    {:ok, count}
  end

  def unwatch_thread(browser_token, board_uri, thread_id)
      when is_binary(browser_token) and is_binary(board_uri) and is_integer(thread_id) do
    browser_token = BrowserIdentity.reference(browser_token)

    valid_thread_ids =
      from(thread in Post,
        join: board in BoardRecord,
        on: board.id == thread.board_id,
        where: thread.id == ^thread_id and is_nil(thread.thread_id) and board.uri == ^board_uri,
        select: thread.id
      )

    {count, _} =
      from(watch in Watch,
        where:
          watch.browser_token == ^browser_token and
            watch.thread_id in subquery(valid_thread_ids)
      )
      |> Repo.delete_all()

    {:ok, count}
  end

  def clear_watches(browser_token) when is_binary(browser_token) do
    browser_token = BrowserIdentity.reference(browser_token)

    {count, _} =
      Repo.delete_all(
        from watch in Watch,
          where: watch.browser_token == ^browser_token
      )

    {:ok, count}
  end

  def reconcile_moved_watches(browser_token, board_uri \\ nil)
      when is_binary(browser_token) and (is_binary(board_uri) or is_nil(board_uri)) do
    browser_token = BrowserIdentity.reference(browser_token)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query =
      from(watch in Watch,
        join: thread in Post,
        on: thread.id == watch.thread_id and is_nil(thread.thread_id),
        join: board in BoardRecord,
        on: board.id == thread.board_id,
        where: watch.browser_token == ^browser_token and watch.board_uri != board.uri,
        update: [set: [board_uri: board.uri, updated_at: ^now]]
      )

    query =
      if is_binary(board_uri) do
        from([watch, _thread, board] in query,
          where: watch.board_uri == ^board_uri or board.uri == ^board_uri
        )
      else
        query
      end

    _ = Repo.update_all(query, [])
    :ok
  end

  def purge_missing_watches(browser_token, board_uri \\ nil)
      when is_binary(browser_token) and (is_binary(board_uri) or is_nil(board_uri)) do
    browser_token = BrowserIdentity.reference(browser_token)
    thread_ids = from(post in Post, where: is_nil(post.thread_id), select: post.id)

    query =
      from watch in Watch,
        where:
          watch.browser_token == ^browser_token and watch.thread_id not in subquery(thread_ids)

    query =
      if is_binary(board_uri),
        do: from(watch in query, where: watch.board_uri == ^board_uri),
        else: query

    Repo.delete_all(query)
  end

  def unwatch_stale_threads(browser_token, board_uri)
      when is_binary(browser_token) and is_binary(board_uri) do
    browser_token = BrowserIdentity.reference(browser_token)
    thread_ids = from(post in Post, where: is_nil(post.thread_id), select: post.id)

    {count, _} =
      from(watch in Watch,
        where:
          watch.browser_token == ^browser_token and watch.board_uri == ^board_uri and
            watch.thread_id not in subquery(thread_ids)
      )
      |> Repo.delete_all()

    {:ok, count}
  end

  def mark_seen(browser_token, board_uri, thread_id, last_seen_post_id)
      when is_binary(browser_token) and is_binary(board_uri) and is_integer(thread_id) and
             is_integer(last_seen_post_id) do
    browser_token = BrowserIdentity.reference(browser_token)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    valid_watch_query =
      from(watch in Watch,
        join: thread in Post,
        on: thread.id == watch.thread_id and is_nil(thread.thread_id),
        join: board in BoardRecord,
        on: board.id == thread.board_id,
        join: seen_post in Post,
        on:
          seen_post.board_id == thread.board_id and seen_post.id == ^last_seen_post_id and
            (seen_post.id == thread.id or seen_post.thread_id == thread.id),
        where:
          watch.browser_token == ^browser_token and watch.thread_id == ^thread_id and
            board.uri == ^board_uri
      )

    {count, _} =
      from([watch, _thread, _board, _seen_post] in valid_watch_query,
        where: fragment("COALESCE(?, 0) < ?", watch.last_seen_post_id, ^last_seen_post_id),
        update: [set: [last_seen_post_id: ^last_seen_post_id, updated_at: ^now]]
      )
      |> Repo.update_all([])

    case count do
      0 -> {:ok, Repo.one(from(watch in valid_watch_query, select: watch))}
      _ -> {:ok, Repo.get_by!(Watch, browser_token: browser_token, thread_id: thread_id)}
    end
  end
end
