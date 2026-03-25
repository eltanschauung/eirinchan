defmodule EirinchanWeb.ThreadWatcherController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Posts
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.ThreadWatcher

  def create(conn, %{"board" => board_uri, "thread_id" => thread_id}) do
    with {:ok, board} <- fetch_board(board_uri),
         {:ok, thread} <- Posts.fetch_thread(board, thread_id),
         {:ok, _watch} <-
           ThreadWatcher.watch_thread(
             conn.assigns.browser_token,
             board.uri,
             thread.id,
             %{last_seen_post_id: thread.id}
           ) do
      watcher_metrics = ThreadWatcher.watch_metrics(conn.assigns.browser_token)

      json(conn, %{
        ok: true,
        watched: true,
        thread_id: PublicIds.public_id(thread),
        board: board.uri,
        watcher_count: watcher_metrics.watcher_count,
        watcher_unread_count: watcher_metrics.watcher_unread_count,
        watcher_you_count: watcher_metrics.watcher_you_count
      })
    else
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      {:error, :thread_not_found} -> send_resp(conn, :not_found, "")
      {:error, _reason} -> send_resp(conn, :unprocessable_entity, "")
    end
  end

  def delete(conn, %{"board" => board_uri, "thread_id" => thread_id}) do
    with {:ok, board} <- fetch_board(board_uri),
         {:ok, _count, public_thread_id} <-
           unwatch_thread(conn.assigns.browser_token, board, thread_id) do
      watcher_metrics = ThreadWatcher.watch_metrics(conn.assigns.browser_token)

      json(conn, %{
        ok: true,
        watched: false,
        thread_id: public_thread_id,
        board: board.uri,
        watcher_count: watcher_metrics.watcher_count,
        watcher_unread_count: watcher_metrics.watcher_unread_count,
        watcher_you_count: watcher_metrics.watcher_you_count
      })
    else
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      {:error, :thread_not_found} -> send_resp(conn, :not_found, "")
      {:error, _reason} -> send_resp(conn, :unprocessable_entity, "")
    end
  end

  def update(conn, %{"board" => board_uri, "thread_id" => thread_id, "last_seen_post_id" => last_seen_post_id}) do
    with {:ok, board} <- fetch_board(board_uri),
         {:ok, thread} <- Posts.fetch_thread(board, thread_id),
         {parsed_last_seen_post_id, ""} <- Integer.parse(to_string(last_seen_post_id)),
         true <- parsed_last_seen_post_id >= PublicIds.public_id(thread),
         {:ok, last_seen_post} <- Posts.get_post(board, parsed_last_seen_post_id),
         {:ok, _watch} <-
           ThreadWatcher.mark_seen(
             conn.assigns.browser_token,
             board.uri,
             thread.id,
             last_seen_post.id
           ) do
      watcher_metrics = ThreadWatcher.watch_metrics(conn.assigns.browser_token)

      json(conn, %{
        ok: true,
        thread_id: PublicIds.public_id(thread),
        last_seen_post_id: parsed_last_seen_post_id,
        watcher_count: watcher_metrics.watcher_count,
        watcher_unread_count: watcher_metrics.watcher_unread_count,
        watcher_you_count: watcher_metrics.watcher_you_count
      })
    else
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      {:error, :thread_not_found} -> send_resp(conn, :not_found, "")
      false -> send_resp(conn, :unprocessable_entity, "")
      :error -> send_resp(conn, :unprocessable_entity, "")
      _ -> send_resp(conn, :unprocessable_entity, "")
    end
  end

  def clear(conn, _params) do
    case conn.assigns[:browser_token] do
      token when is_binary(token) ->
        {:ok, _count} = ThreadWatcher.clear_watches(token)

        json(conn, %{
          ok: true,
          watcher_count: 0,
          watcher_unread_count: 0,
          watcher_you_count: 0
        })

      _ ->
        send_resp(conn, :unprocessable_entity, "")
    end
  end

  defp fetch_board(uri) do
    case Boards.get_board_by_uri(uri) do
      nil -> {:error, :not_found}
      board -> {:ok, board}
    end
  end

  defp unwatch_thread(browser_token, board, thread_id) do
    case Posts.fetch_thread(board, thread_id) do
      {:ok, thread} ->
        with {:ok, count} <- ThreadWatcher.unwatch_thread(browser_token, board.uri, thread.id) do
          {:ok, count, PublicIds.public_id(thread)}
        end

      {:error, :thread_not_found} ->
        case Integer.parse(to_string(thread_id)) do
          {public_thread_id, ""} ->
            with {:ok, count} <- ThreadWatcher.unwatch_stale_threads(browser_token, board.uri),
                 true <- count > 0 do
              {:ok, count, public_thread_id}
            else
              _ -> {:error, :thread_not_found}
            end

          _ ->
            {:error, :thread_not_found}
        end
    end
  end
end
