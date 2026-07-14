defmodule Eirinchan.Tf2PlayerCountTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Tf2PlayerCount

  test "parses a successful player-count response and removes whitespace" do
    assert {:ok, stats} =
             Tf2PlayerCount.parse_response(
               ~s({"display":"12 / 42","success":true,"player_count":12,"visible_max":42})
             )

    assert stats == %{display: "12/42", player_count: 12, available?: true}
  end

  test "rejects unsuccessful, malformed, and inconsistent responses" do
    assert {:error, :invalid_response} =
             Tf2PlayerCount.parse_response(
               ~s({"display":"0 / 42","success":false,"player_count":0})
             )

    assert {:error, :invalid_response} = Tf2PlayerCount.parse_response("not json")

    assert {:error, :inconsistent_response} =
             Tf2PlayerCount.parse_response(
               ~s({"display":"9 / 42","success":true,"player_count":8})
             )
  end

  test "rejects display text that is not a bounded numeric ratio" do
    assert {:error, :invalid_response} =
             Tf2PlayerCount.parse_response(
               ~S|{"display":"<script>alert(1)</script>","success":true,"player_count":1}|
             )
  end
end
