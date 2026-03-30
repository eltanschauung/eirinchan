alias Eirinchan.Boards.BoardRecord
alias Eirinchan.Posts.Post
alias Eirinchan.Repo
alias Eirinchan.Runtime.Config

import Ecto.Query

parse_id = fn
  value when is_integer(value) ->
    value

  value when is_binary(value) ->
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> raise "invalid thread id: #{inspect(value)}"
    end
end

run = fn board_uri, thread_id ->
  board = Repo.get_by!(BoardRecord, uri: board_uri)
  config = Config.compose(nil, %{}, board.config_overrides, request_host: "bantculture.com")

  thread =
    Repo.one!(
      from post in Post,
        where:
          post.board_id == ^board.id and is_nil(post.thread_id) and post.public_id == ^parse_id.(thread_id)
    )

  metrics =
    Repo.one(
      from reply in Post,
        where: reply.board_id == ^board.id and reply.thread_id == ^thread.id,
        select: %{
          reply_count: count(reply.id),
          image_count: filter(count(reply.id), not is_nil(reply.file_path))
        }
    ) || %{reply_count: 0, image_count: 0}

  age_seconds =
    thread.inserted_at
    |> DateTime.diff(DateTime.utc_now(), :second)
    |> Kernel.abs()
    |> max(1)

  eligible =
    (metrics.reply_count > 0 or metrics.image_count > 0) and
      metrics.reply_count < config.early_404_gap_max

  score =
    if eligible do
      ceil((2 * (metrics.reply_count + metrics.image_count * 3)) / (age_seconds / 3600) * 100)
    end

  IO.inspect(%{
    board: board.uri,
    public_id: thread.public_id,
    internal_id: thread.id,
    inserted_at: thread.inserted_at,
    age_seconds: age_seconds,
    replies: metrics.reply_count,
    images: metrics.image_count,
    sticky: thread.sticky,
    inactive: thread.inactive,
    eligible: eligible,
    score: score,
    max_replies: config.early_404_gap_max,
    warning_threshold: config.early_404_gap_warning,
    deletion_threshold: config.early_404_gap_deletion,
    would_warn: eligible and not thread.sticky and score <= config.early_404_gap_warning,
    would_delete: eligible and not thread.sticky and score <= config.early_404_gap_deletion
  })
end

case System.argv() do
  [thread_id] ->
    run.("bant", thread_id)

  [board_uri, thread_id] ->
    run.(board_uri, thread_id)

  _ ->
    IO.puts("usage: mix run priv/scripts/gap_score.exs [board_uri] <thread_public_id>")
    System.halt(1)
end
