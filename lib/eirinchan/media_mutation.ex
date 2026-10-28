defmodule Eirinchan.MediaMutation do
  @moduledoc false

  def with_post(board, post_id, repo, fun, missing \\ :not_found) do
    case Eirinchan.Posts.get_post(board, post_id, repo: repo) do
      {:ok, post} ->
        thread_id = post.thread_id || post.id

        with_thread(thread_id, fn ->
          # A move may have completed between initial lookup and acquisition.
          # Do not run under a stale thread's lock or operate on a reused ID.
          case Eirinchan.Posts.get_post(board, post_id, repo: repo) do
            {:ok, current} ->
              if current.id == post.id and (current.thread_id || current.id) == thread_id,
                do: fun.(),
                else: {:error, :stale_media}

            _ ->
              {:error, :stale_media}
          end
        end)

      _ ->
        {:error, missing}
    end
  end

  defp with_thread(thread_id, fun) do
    key = {__MODULE__, thread_id}

    cond do
      not Eirinchan.LockAuthority.available?() ->
        {:error, :stale_media}

      Process.get(key, false) ->
        fun.()

      true ->
        result =
          :global.trans(
            {key, self()},
            fn ->
              if Eirinchan.LockAuthority.available?() do
                Process.put(key, true)

                try do
                  fun.()
                after
                  Process.delete(key)
                end
              else
                {:error, :stale_media}
              end
            end,
            [node()],
            0
          )

        if result == :aborted, do: {:error, :stale_media}, else: result
    end
  end
end
