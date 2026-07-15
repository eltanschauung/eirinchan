defmodule Eirinchan.Stats do
  @moduledoc false

  import Ecto.Query

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

  @spec active_browsers_10minutes() :: non_neg_integer()
  def active_browsers_10minutes, do: BrowserPresence.active_browsers_10minutes()

  @spec users_10minutes() :: non_neg_integer()
  def users_10minutes, do: active_browsers_10minutes()
end
