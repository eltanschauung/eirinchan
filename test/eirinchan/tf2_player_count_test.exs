defmodule Eirinchan.Tf2PlayerCountTest do
  use ExUnit.Case, async: false

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

  test "reads and bounds the Bant instance cache interval" do
    previous_path = Application.get_env(:eirinchan, :instance_config_path)
    path = Path.join(System.tmp_dir!(), "eirinchan-tf2-config-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(%{tf2_player_count_cache_seconds: 9_000}))

    on_exit(fn ->
      if is_nil(previous_path),
        do: Application.delete_env(:eirinchan, :instance_config_path),
        else: Application.put_env(:eirinchan, :instance_config_path, previous_path)

      File.rm(path)
    end)

    Application.put_env(:eirinchan, :instance_config_path, path)
    assert Tf2PlayerCount.cache_seconds() == 3_600
  end
end
