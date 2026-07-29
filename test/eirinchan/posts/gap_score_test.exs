defmodule Eirinchan.Posts.GapScoreTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Posts.GapScore

  test "zero-reply threads age out twice as fast as one-reply threads" do
    now = ~U[2026-07-29 12:00:00Z]
    inserted_at = DateTime.add(now, -50 * 60 * 60, :second)

    assert GapScore.calculate(inserted_at, 0, 0, now: now) == 2
    assert GapScore.calculate(inserted_at, 1, 0, now: now) == 4
  end

  test "zero-reply threads remain eligible below the maximum reply threshold" do
    assert GapScore.eligible?(0, 100)
    assert GapScore.eligible?(99, 100)
    refute GapScore.eligible?(100, 100)
  end
end
