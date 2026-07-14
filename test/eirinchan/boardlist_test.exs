defmodule Eirinchan.BoardlistTest do
  use ExUnit.Case, async: false

  alias Eirinchan.Boardlist
  alias Eirinchan.Settings
  alias EirinchanWeb.{FragmentCache, PostView}

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

    FragmentCache.clear()

    boards = [
      %{id: 1, uri: "desk", title: "Desktop Board"},
      %{id: 2, uri: "phone", title: "Mobile Board"}
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

  test "runtime boardlist labels support global message placeholders and inline conditions", %{
    boards: boards
  } do
    label = "TF2 {if tf2_display > 0}TF2 playercount: {tf2_display}/24"

    :ok =
      Settings.persist_instance_config(%{
        boardlist: %{
          desktop: [%{label => "https://kogasa.tf"}],
          mobile: [%{label => "https://kogasa.tf"}]
        }
      })

    [online_group] =
      PostView.boardlist_groups(boards,
        variant: :desktop,
        tf2_now: 6_000,
        tf2_fetcher: fn ->
          {:ok, %{"success" => true, "display" => "16", "player_count" => 16}}
        end
      )

    assert [%{label: "TF2 TF2 playercount: 16/24", title: "TF2 TF2 playercount: 16/24"} = link] =
             online_group

    assert link.href == "https://kogasa.tf"

    FragmentCache.clear()

    [offline_group] =
      PostView.boardlist_groups(boards,
        variant: :desktop,
        tf2_now: 6_000,
        tf2_fetcher: fn ->
          {:ok, %{"success" => true, "display" => "0", "player_count" => 0}}
        end
      )

    assert [%{label: "TF2", title: "TF2", href: "https://kogasa.tf"}] = offline_group
    assert Boardlist.encode_for_edit(boards) =~ label
  end

  test "rejects script, protocol-relative, and credential-bearing boardlist links", %{
    boards: boards
  } do
    raw =
      Jason.encode!(%{
        "desktop" => [
          %{
            "Safe" => "https://example.com/path",
            "Local" => "/news",
            "Script" => "javascript:alert(1)",
            "Protocol relative" => "//evil.example/path",
            "Credentials" => "https://user:pass@example.com/path"
          }
        ]
      })

    assert {:ok, _groups} = Boardlist.update_from_json(raw, boards)

    [links] = Boardlist.configured_groups(boards, variant: :desktop)
    assert links |> Enum.map(& &1.label) |> MapSet.new() == MapSet.new(["Local", "Safe"])
  end
end
