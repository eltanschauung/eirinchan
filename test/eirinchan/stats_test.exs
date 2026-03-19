defmodule Eirinchan.StatsTest do
  use Eirinchan.DataCase

  alias Eirinchan.BrowserPresence
  alias Eirinchan.Stats

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
    :ok
  end

  test "posts_perhour counts posts from the past hour for a board" do
    board = board_fixture()
    thread = thread_fixture(board)

    recent_reply = reply_fixture(board, thread)
    old_reply = reply_fixture(board, thread)

    Eirinchan.Repo.update_all(
      Ecto.Query.from(p in Eirinchan.Posts.Post, where: p.id == ^old_reply.id),
      set: [inserted_at: DateTime.utc_now() |> DateTime.add(-2 * 60 * 60, :second)]
    )

    assert Stats.posts_perhour(board) == 2
    assert Stats.posts_perhour(board.id) == 2
    assert recent_reply.id != old_reply.id
  end

  test "users_10minutes counts tracked browser presence" do
    BrowserPresence.touch("token-1234567890123456")
    BrowserPresence.touch("token-abcdefghijklmnop")

    assert Stats.users_10minutes() == 2
  end
end
