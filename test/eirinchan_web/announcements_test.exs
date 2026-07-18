defmodule EirinchanWeb.AnnouncementsTest do
  use Eirinchan.DataCase, async: false

  alias EirinchanWeb.Announcements
  alias EirinchanWeb.FragmentCache

  setup do
    FragmentCache.clear()
    :ok
  end

  test "global messages expand the threads-per-hour placeholder" do
    board = board_fixture()
    _thread = thread_fixture(board)

    assert Announcements.global_message(
             %{global_message: "TPH: {stats.threads_perhour}"},
             board: board
           ) == "TPH: 1"
  end
end
