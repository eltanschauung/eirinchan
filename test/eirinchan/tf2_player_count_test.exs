defmodule Eirinchan.Tf2PlayerCountTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Tf2PlayerCount

  test "preserves the API display string exactly" do
    assert {:ok, stats} =
             Tf2PlayerCount.parse_response(
               ~s({"display":"12 / 42","success":true,"player_count":12,"visible_max":42})
             )

    assert stats == %{display: "12 / 42", player_count: 12, available?: true}
  end

  test "accepts a plain numeric display value" do
    assert {:ok, stats} =
             Tf2PlayerCount.parse_response(
               ~s({"display":"16","success":true,"player_count":16,"visible_max":42})
             )

    assert stats == %{display: "16", player_count: 16, available?: true}
  end

  test "rejects unsuccessful and malformed responses" do
    assert {:error, :invalid_response} =
             Tf2PlayerCount.parse_response(
               ~s({"display":"0 / 42","success":false,"player_count":0})
             )

    assert {:error, :invalid_response} = Tf2PlayerCount.parse_response("not json")

    assert {:error, :invalid_response} =
             Tf2PlayerCount.parse_response(~s({"display":"","success":true,"player_count":8}))
  end

  test "rejects control characters in display text" do
    assert {:error, :invalid_response} =
             Tf2PlayerCount.parse_response(
               ~S|{"display":"16\nplayers","success":true,"player_count":16}|
             )
  end
end
