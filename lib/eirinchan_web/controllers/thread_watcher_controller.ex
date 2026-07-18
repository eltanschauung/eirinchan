defmodule EirinchanWeb.ThreadWatcherController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Posts
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings
  alias Eirinchan.ThreadWatcher

  def create(conn, %{"board" => board_uri, "thread_id" => thread_id}) do
    with {:ok, board} <- fetch_board(board_uri),
         {:ok, thread} <- Posts.fetch_thread(board, thread_id),
         {:ok, _watch} <-
           ThreadWatcher.watch_thread(
             conn.assigns.browser_token,
             board.uri,
             thread.id,
             %{last_seen_post_id: thread.id},
             max_threads: watcher_max_threads()
           ) do
      json(
        conn,
        Map.merge(
          %{
            ok: true,
            watched: true,
            thread_id: PublicIds.public_id(thread),
            board: board.uri
          },
          watcher_metrics(conn.assigns.browser_token)
        )
      )
    else
      {:error, :not_found} ->
        send_resp(conn, :not_found, "")

      {:error, :thread_not_found} ->
        send_resp(conn, :not_found, "")

      {:error, :watch_limit} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "watch_limit", message: "Watcher thread limit reached."})
    end
  end

  def delete(conn, %{"board" => board_uri, "thread_id" => thread_id}) do
    with {:ok, board} <- fetch_board(board_uri),
         {:ok, _count, public_thread_id} <-
           unwatch_thread(conn.assigns.browser_token, board, thread_id) do
      json(
        conn,
        Map.merge(
          %{
            ok: true,
            watched: false,
            thread_id: public_thread_id,
            board: board.uri
          },
          watcher_metrics(conn.assigns.browser_token)
        )
      )
    else
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      {:error, :thread_not_found} -> send_resp(conn, :not_found, "")
    end
  end

  def update(conn, %{
        "board" => board_uri,
        "thread_id" => thread_id,
        "last_seen_post_id" => last_seen_post_id
      }) do
    with {:ok, board} <- fetch_board(board_uri),
         {:ok, thread} <- Posts.fetch_thread(board, thread_id),
         {parsed_last_seen_post_id, ""} <- Integer.parse(to_string(last_seen_post_id)),
         true <- parsed_last_seen_post_id >= PublicIds.public_id(thread),
         {:ok, last_seen_post} <- Posts.get_post(board, parsed_last_seen_post_id),
         true <- post_belongs_to_thread?(last_seen_post, thread),
         {:ok, _watch} <-
           ThreadWatcher.mark_seen(
             conn.assigns.browser_token,
             board.uri,
             thread.id,
             last_seen_post.id
           ) do
      json(
        conn,
        Map.merge(
          %{
            ok: true,
            thread_id: PublicIds.public_id(thread),
            last_seen_post_id: parsed_last_seen_post_id
          },
          watcher_metrics(conn.assigns.browser_token)
        )
      )
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

  defp watcher_metrics(browser_token) do
    browser_token
    |> ThreadWatcher.watch_metrics()
    |> Map.take([:watcher_count, :watcher_unread_count, :watcher_you_count])
  end

  defp watcher_max_threads do
    Settings.current_instance_config()
    |> then(&Config.compose(nil, &1, %{}))
    |> Map.fetch!(:watcher_max_threads)
  end

  defp post_belongs_to_thread?(post, thread) do
    post.id == thread.id or post.thread_id == thread.id
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
            {:ok, count} = ThreadWatcher.unwatch_stale_threads(browser_token, board.uri)
            {:ok, count, public_thread_id}

          _ ->
            {:error, :thread_not_found}
        end
    end
  end
end
