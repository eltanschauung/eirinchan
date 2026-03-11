defmodule EirinchanWeb.ThreadWatcherController do
  use EirinchanWeb, :controller

  alias Eirinchan.Boards
  alias Eirinchan.Posts
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
      json(conn, %{ok: true, watched: true, thread_id: thread.id, board: board.uri})
    else
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      {:error, :thread_not_found} -> send_resp(conn, :not_found, "")
      {:error, _reason} -> send_resp(conn, :unprocessable_entity, "")
    end
  end

  def delete(conn, %{"board" => board_uri, "thread_id" => thread_id}) do
    with {:ok, board} <- fetch_board(board_uri),
         {:ok, thread} <- Posts.fetch_thread(board, thread_id),
         {:ok, _count} <-
           ThreadWatcher.unwatch_thread(conn.assigns.browser_token, board.uri, thread.id) do
      json(conn, %{ok: true, watched: false, thread_id: thread.id, board: board.uri})
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
         true <- parsed_last_seen_post_id >= thread.id,
         {:ok, _watch} <-
           ThreadWatcher.mark_seen(
             conn.assigns.browser_token,
             board.uri,
             thread.id,
             parsed_last_seen_post_id
           ) do
      json(conn, %{ok: true, thread_id: thread.id, last_seen_post_id: parsed_last_seen_post_id})
    else
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      {:error, :thread_not_found} -> send_resp(conn, :not_found, "")
      false -> send_resp(conn, :unprocessable_entity, "")
      :error -> send_resp(conn, :unprocessable_entity, "")
      _ -> send_resp(conn, :unprocessable_entity, "")
    end
  end

  defp fetch_board(uri) do
    case Boards.get_board_by_uri(uri) do
      nil -> {:error, :not_found}
      board -> {:ok, board}
    end
  end
end
