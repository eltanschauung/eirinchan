defmodule Eirinchan.ThreadWatcher do
  import Ecto.Query, warn: false

  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  alias Eirinchan.ThreadWatcher.Snapshot
  alias Eirinchan.ThreadWatcher.Watch

  @default_max_threads 500

  def snapshot(browser_identity, opts \\ []) when is_binary(browser_identity) do
    Snapshot.build(browser_identity, opts)
  end

  def empty_snapshot, do: Snapshot.empty()

  def list_watches(browser_identity) when is_binary(browser_identity) do
    browser_ref = BrowserIdentity.reference(browser_identity)

    from(watch in Watch,
      join: thread in Post,
      on: thread.id == watch.thread_id and is_nil(thread.thread_id),
      join: board in BoardRecord,
      on: board.id == thread.board_id,
      where: watch.browser_ref == ^browser_ref,
      order_by: [asc: board.uri, desc: watch.updated_at],
      select: {watch, board.uri}
    )
    |> Repo.all()
    |> Enum.map(fn {watch, board_uri} -> %{watch | board_uri: board_uri} end)
  end

  def list_watch_summaries(browser_identity) when is_binary(browser_identity) do
    browser_identity
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

  def watched_thread_ids(browser_identity, board_uri)
      when is_binary(browser_identity) and is_binary(board_uri) do
    browser_ref = BrowserIdentity.reference(browser_identity)

    from(watch in Watch,
      join: thread in Post,
      on: thread.id == watch.thread_id and is_nil(thread.thread_id),
      join: board in BoardRecord,
      on: board.id == thread.board_id,
      where: watch.browser_ref == ^browser_ref and board.uri == ^board_uri,
      select: watch.thread_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def watch_state_for_board(browser_identity, board_uri)
      when is_binary(browser_identity) and is_binary(board_uri) do
    browser_identity
    |> snapshot()
    |> Map.fetch!(:watch_state_by_board)
    |> Map.get(board_uri, %{})
  end

  def watch_count(browser_identity) when is_binary(browser_identity) do
    browser_identity
    |> watch_metrics()
    |> Map.fetch!(:watcher_count)
  end

  def watch_metrics(browser_identity) when is_binary(browser_identity) do
    browser_identity
    |> snapshot()
    |> Map.fetch!(:metrics)
  end

  def watched?(browser_identity, board_uri, thread_id)
      when is_binary(browser_identity) and is_binary(board_uri) and is_integer(thread_id) do
    browser_ref = BrowserIdentity.reference(browser_identity)

    Repo.exists?(
      from watch in Watch,
        join: thread in Post,
        on: thread.id == watch.thread_id and is_nil(thread.thread_id),
        join: board in BoardRecord,
        on: board.id == thread.board_id,
        where:
          watch.browser_ref == ^browser_ref and board.uri == ^board_uri and
            watch.thread_id == ^thread_id
    )
  end

  def watch_thread(browser_identity, board_uri, thread_id, attrs \\ %{}, opts \\ [])
      when is_binary(browser_identity) and is_binary(board_uri) and is_integer(thread_id) do
    browser_ref = BrowserIdentity.reference(browser_identity)
    attrs = Map.new(attrs)
    max_threads = Config.positive_integer(Keyword.get(opts, :max_threads), @default_max_threads)

    last_seen_post_id =
      Map.get(attrs, :last_seen_post_id, Map.get(attrs, "last_seen_post_id"))

    insert_attrs =
      attrs
      |> Map.drop([:last_seen_post_id, "last_seen_post_id"])
      |> Map.put(:browser_ref, browser_ref)
      |> Map.put(:board_uri, board_uri)
      |> Map.put(:thread_id, thread_id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with_browser_lock(browser_ref, fn ->
      unless watch_capacity_available?(browser_ref, thread_id, max_threads) do
        Repo.rollback(:watch_limit)
      end

      case %Watch{}
           |> Watch.changeset(insert_attrs)
           |> Repo.insert(
             on_conflict: [set: [board_uri: board_uri, updated_at: now]],
             conflict_target: [:browser_ref, :thread_id]
           ) do
        {:ok, proposed_watch} ->
          if proposed_watch.activated do
            from(watch in Watch,
              where: watch.browser_ref == ^browser_ref and watch.thread_id == ^thread_id
            )
            |> Repo.update_all(set: [activated: true, updated_at: now])
          end

          case last_seen_post_id do
            value when is_integer(value) ->
              case do_mark_seen(browser_ref, board_uri, thread_id, value, now) do
                %Watch{} = watch -> watch
                nil -> Repo.rollback(:invalid_last_seen_post)
              end

            _ ->
              Repo.get_by!(Watch, browser_ref: browser_ref, thread_id: thread_id)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp with_browser_lock(browser_ref, callback) do
    Repo.transaction(fn ->
      lock_browser_state(browser_ref)
      callback.()
    end)
  end

  defp lock_browser_state(browser_ref) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [browser_ref])
    :ok
  end

  defp watch_capacity_available?(browser_ref, thread_id, max_threads) do
    Repo.exists?(
      from watch in Watch,
        where: watch.browser_ref == ^browser_ref and watch.thread_id == ^thread_id
    ) or
      Repo.aggregate(
        from(watch in Watch, where: watch.browser_ref == ^browser_ref),
        :count
      ) < max_threads
  end

  def activate_for_reply(thread_id, excluded_browser_identity \\ nil)
      when is_integer(thread_id) and
             (is_binary(excluded_browser_identity) or is_nil(excluded_browser_identity)) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query =
      from(watch in Watch,
        where: watch.thread_id == ^thread_id and not watch.activated
      )

    query =
      if is_binary(excluded_browser_identity) do
        excluded_browser_ref = BrowserIdentity.reference(excluded_browser_identity)
        from(watch in query, where: watch.browser_ref != ^excluded_browser_ref)
      else
        query
      end

    {count, _} = Repo.update_all(query, set: [activated: true, updated_at: now])
    {:ok, count}
  end

  def unwatch_thread(browser_identity, board_uri, thread_id)
      when is_binary(browser_identity) and is_binary(board_uri) and is_integer(thread_id) do
    browser_ref = BrowserIdentity.reference(browser_identity)

    valid_thread_ids =
      from(thread in Post,
        join: board in BoardRecord,
        on: board.id == thread.board_id,
        where: thread.id == ^thread_id and is_nil(thread.thread_id) and board.uri == ^board_uri,
        select: thread.id
      )

    with_browser_lock(browser_ref, fn ->
      {count, _} =
        from(watch in Watch,
          where:
            watch.browser_ref == ^browser_ref and
              watch.thread_id in subquery(valid_thread_ids)
        )
        |> Repo.delete_all()

      count
    end)
  end

  def clear_watches(browser_identity) when is_binary(browser_identity) do
    browser_ref = BrowserIdentity.reference(browser_identity)

    with_browser_lock(browser_ref, fn ->
      {count, _} =
        Repo.delete_all(
          from watch in Watch,
            where: watch.browser_ref == ^browser_ref
        )

      count
    end)
  end

  def reconcile_moved_watches(browser_identity, board_uri \\ nil)
      when is_binary(browser_identity) and (is_binary(board_uri) or is_nil(board_uri)) do
    browser_ref = BrowserIdentity.reference(browser_identity)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query =
      from(watch in Watch,
        join: thread in Post,
        on: thread.id == watch.thread_id and is_nil(thread.thread_id),
        join: board in BoardRecord,
        on: board.id == thread.board_id,
        where: watch.browser_ref == ^browser_ref and watch.board_uri != board.uri,
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

    {:ok, :ok} =
      with_browser_lock(browser_ref, fn ->
        _ = Repo.update_all(query, [])
        :ok
      end)

    :ok
  end

  def purge_missing_watches(browser_identity, board_uri \\ nil)
      when is_binary(browser_identity) and (is_binary(board_uri) or is_nil(board_uri)) do
    browser_ref = BrowserIdentity.reference(browser_identity)
    thread_ids = from(post in Post, where: is_nil(post.thread_id), select: post.id)

    query =
      from watch in Watch,
        where: watch.browser_ref == ^browser_ref and watch.thread_id not in subquery(thread_ids)

    query =
      if is_binary(board_uri),
        do: from(watch in query, where: watch.board_uri == ^board_uri),
        else: query

    case with_browser_lock(browser_ref, fn -> Repo.delete_all(query) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def unwatch_stale_threads(browser_identity, board_uri)
      when is_binary(browser_identity) and is_binary(board_uri) do
    browser_ref = BrowserIdentity.reference(browser_identity)
    thread_ids = from(post in Post, where: is_nil(post.thread_id), select: post.id)

    with_browser_lock(browser_ref, fn ->
      {count, _} =
        from(watch in Watch,
          where:
            watch.browser_ref == ^browser_ref and watch.board_uri == ^board_uri and
              watch.thread_id not in subquery(thread_ids)
        )
        |> Repo.delete_all()

      count
    end)
  end

  def mark_seen(browser_identity, board_uri, thread_id, last_seen_post_id)
      when is_binary(browser_identity) and is_binary(board_uri) and is_integer(thread_id) and
             is_integer(last_seen_post_id) do
    browser_ref = BrowserIdentity.reference(browser_identity)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with_browser_lock(browser_ref, fn ->
      do_mark_seen(browser_ref, board_uri, thread_id, last_seen_post_id, now)
    end)
  end

  defp do_mark_seen(browser_ref, board_uri, thread_id, last_seen_post_id, now) do
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
          watch.browser_ref == ^browser_ref and watch.thread_id == ^thread_id and
            board.uri == ^board_uri
      )

    {count, _} =
      from([watch, _thread, _board, _seen_post] in valid_watch_query,
        where: fragment("COALESCE(?, 0) < ?", watch.last_seen_post_id, ^last_seen_post_id),
        update: [set: [last_seen_post_id: ^last_seen_post_id, updated_at: ^now]]
      )
      |> Repo.update_all([])

    case count do
      0 -> Repo.one(from(watch in valid_watch_query, select: watch))
      _ -> Repo.get_by!(Watch, browser_ref: browser_ref, thread_id: thread_id)
    end
  end
end
