defmodule Eirinchan.Stats do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.AprilFoolsTeams
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.BrowserPresence
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo

  @spec posts_perhour(BoardRecord.t() | integer() | [integer()], keyword()) :: integer()
  def posts_perhour(target, opts \\ [])

  def posts_perhour(%BoardRecord{id: board_id}, opts), do: posts_perhour(board_id, opts)
  def posts_perhour(board_id, opts) when is_integer(board_id), do: posts_perhour([board_id], opts)

  def posts_perhour(board_ids, opts) when is_list(board_ids) do
    count_perhour(board_ids, opts, false)
  end

  @spec threads_perhour(BoardRecord.t() | integer() | [integer()], keyword()) :: integer()
  def threads_perhour(target, opts \\ [])

  def threads_perhour(%BoardRecord{id: board_id}, opts), do: threads_perhour(board_id, opts)

  def threads_perhour(board_id, opts) when is_integer(board_id),
    do: threads_perhour([board_id], opts)

  def threads_perhour(board_ids, opts) when is_list(board_ids) do
    count_perhour(board_ids, opts, true)
  end

  defp count_perhour(board_ids, opts, threads_only?) do
    repo = Keyword.get(opts, :repo, Repo)
    now = Keyword.get(opts, :now, DateTime.utc_now(:second)) |> DateTime.truncate(:second)
    hour_cutoff = DateTime.add(now, -60 * 60, :second)

    query =
      from post in Post,
        where:
          post.board_id in ^board_ids and post.inserted_at > ^hour_cutoff and
            post.inserted_at <= ^now

    query = if threads_only?, do: from(post in query, where: is_nil(post.thread_id)), else: query

    repo.aggregate(query, :count, :id) || 0
  end

  @spec active_browsers_10minutes(keyword()) :: non_neg_integer()
  def active_browsers_10minutes(opts \\ []), do: BrowserPresence.active_browsers_10minutes(opts)

  @spec users_10minutes(keyword()) :: non_neg_integer()
  def users_10minutes(opts \\ []), do: active_browsers_10minutes(opts)

  @spec users_24hours(keyword()) :: non_neg_integer()
  def users_24hours(opts \\ []), do: BrowserPresence.active_browsers(24 * 60 * 60, opts)

  def team_variable(name) when is_binary(name) do
    AprilFoolsTeams.dynamic_team_variable(name)
  end

  for team_id <- 1..12 do
    def unquote(String.to_atom("team_#{team_id}"))() do
      AprilFoolsTeams.team_tuple(unquote(team_id))
    end
  end
end
