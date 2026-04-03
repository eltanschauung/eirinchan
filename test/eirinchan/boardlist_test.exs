defmodule Eirinchan.BoardlistTest do
  use ExUnit.Case, async: false

  alias Eirinchan.Boardlist
  alias Eirinchan.Settings

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-boardlist-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    boards = [
      %{uri: "desk", title: "Desktop Board"},
      %{uri: "phone", title: "Mobile Board"}
    ]

    {:ok, boards: boards, path: path}
  end

  test "legacy flat boardlist config is reused for desktop and mobile", %{boards: boards} do
    :ok =
      Settings.persist_instance_config(%{
        boardlist: [
          ["desk"],
          %{"Home" => "/"}
        ]
      })

    desktop = Boardlist.configured_groups(boards, variant: :desktop)
    mobile = Boardlist.configured_groups(boards, variant: :mobile)

    assert desktop == mobile
    assert Enum.at(desktop, 0) |> Enum.at(0) |> Map.fetch!(:label) == "desk"
  end

  test "structured boardlist config selects the requested variant", %{boards: boards} do
    :ok =
      Settings.persist_instance_config(%{
        boardlist: %{
          desktop: [["desk"]],
          mobile: [["phone"]]
        }
      })

    desktop = Boardlist.configured_groups(boards, variant: :desktop)
    mobile = Boardlist.configured_groups(boards, variant: :mobile)

    assert Enum.at(desktop, 0) |> Enum.at(0) |> Map.fetch!(:label) == "desk"
    assert Enum.at(mobile, 0) |> Enum.at(0) |> Map.fetch!(:label) == "phone"
  end

  test "encode_for_edit outputs desktop and mobile sections", %{boards: boards} do
    :ok =
      Settings.persist_instance_config(%{
        boardlist: %{
          desktop: [["desk"]],
          mobile: [["phone"]]
        }
      })

    encoded = Boardlist.encode_for_edit(boards)

    assert encoded =~ ~s("desktop")
    assert encoded =~ ~s("mobile")
    assert encoded =~ ~s("desk")
    assert encoded =~ ~s("phone")
  end
end
