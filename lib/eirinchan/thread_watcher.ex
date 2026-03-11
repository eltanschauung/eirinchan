defmodule Eirinchan.ThreadWatcher do
  import Ecto.Query, warn: false

  alias Eirinchan.Repo
  alias Eirinchan.ThreadWatcher.Watch

  def list_watches(browser_token) when is_binary(browser_token) do
    Watch
    |> where([watch], watch.browser_token == ^browser_token)
    |> order_by([watch], asc: watch.board_uri, desc: watch.updated_at)
    |> Repo.all()
  end

  def watched_thread_ids(browser_token, board_uri)
      when is_binary(browser_token) and is_binary(board_uri) do
    Watch
    |> where([watch], watch.browser_token == ^browser_token and watch.board_uri == ^board_uri)
    |> select([watch], watch.thread_id)
    |> Repo.all()
    |> MapSet.new()
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
    watch_thread(browser_token, board_uri, thread_id, %{last_seen_post_id: last_seen_post_id})
  end
end
