defmodule Eirinchan.MediaMutation do
  @moduledoc false

  def with_post(board, post_id, repo, fun, missing \\ :not_found) do
    case Eirinchan.Posts.get_post(board, post_id, repo: repo) do
      {:ok, post} -> with_thread(post.thread_id || post.id, fun)
      _ -> {:error, missing}
    end
  end

  defp with_thread(thread_id, fun) do
    key = {__MODULE__, thread_id}

    if Process.get(key, false) do
      fun.()
    else
      result =
        :global.trans(
          {key, self()},
          fn ->
            Process.put(key, true)

            try do
              fun.()
            after
              Process.delete(key)
            end
          end,
          [node()],
          0
        )

      if result == :aborted, do: {:error, :stale_media}, else: result
    end
  end
end
