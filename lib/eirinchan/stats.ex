defmodule Eirinchan.Stats do
  @moduledoc false

  import Ecto.Query

  alias Eirinchan.AprilFoolsTeams
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.BrowserPresence
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo

  @spec posts_perhour(BoardRecord.t() | integer() | [integer()]) :: integer()
  def posts_perhour(%BoardRecord{id: board_id}), do: posts_perhour(board_id)

  def posts_perhour(board_id) when is_integer(board_id) do
    posts_perhour([board_id])
  end

  def posts_perhour(board_ids) when is_list(board_ids) do
    hour_cutoff = DateTime.utc_now() |> DateTime.add(-60 * 60, :second)

    Repo.aggregate(
      from(post in Post, where: post.board_id in ^board_ids and post.inserted_at > ^hour_cutoff),
      :count,
      :id
    ) || 0
  end

  @spec users_10minutes() :: integer()
  def users_10minutes do
    BrowserPresence.users_10minutes()
  end

  def team_variable(name) when is_binary(name) do
    AprilFoolsTeams.dynamic_team_variable(name)
  end

  for team_id <- 1..12 do
    def unquote(String.to_atom("team_#{team_id}"))() do
      AprilFoolsTeams.team_tuple(unquote(team_id))
    end
  end
end
