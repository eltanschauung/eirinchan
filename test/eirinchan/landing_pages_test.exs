defmodule Eirinchan.LandingPagesTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.Boards
  alias Eirinchan.Boards.BoardRecord
  alias Eirinchan.LandingPages

  test "public boards use snapshotted PPD, exclusions, and descending post counters" do
    active = board_fixture(%{uri: "active", title: "Active Board"})
    established = board_fixture(%{uri: "established", title: "Established Board"})
    excluded = board_fixture(%{uri: "private", title: "Excluded Board"})

    Repo.update_all(from(board in BoardRecord, where: board.id == ^active.id),
      set: [next_public_post_id: 101]
    )

    Repo.update_all(from(board in BoardRecord, where: board.id == ^established.id),
      set: [next_public_post_id: 500_001]
    )

    Repo.update_all(from(board in BoardRecord, where: board.id == ^excluded.id),
      set: [next_public_post_id: 900_001]
    )

    boards = Boards.list_boards()
    board_ids = LandingPages.board_ids(%{"exclude" => excluded.uri}, boards)

    summaries =
      LandingPages.public_boards(boards, board_ids, %{
        Integer.to_string(active.id) => 2,
        Integer.to_string(excluded.id) => 9
      })

    assert Enum.map(summaries, & &1.uri) == ["established", "active"]
    assert Enum.map(summaries, & &1.ppd) == [0, 2]
    assert Enum.map(summaries, & &1.total_posts_text) == ["500,000", "100"]
  end
end
