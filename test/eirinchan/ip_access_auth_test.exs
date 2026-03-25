defmodule Eirinchan.IpAccessAuthTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.IpAccessAuth
  alias Eirinchan.IpAccessEntry

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-ipauth-settings-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)
    Repo.delete_all(IpAccessEntry)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  test "uses no passwords when configured list is blank" do
    config = IpAccessAuth.effective_config(%{passwords: ""})
    assert config.passwords == []
  end

  test "normalizes comma-separated passwords and deduplicates case-insensitively" do
    config = IpAccessAuth.effective_config(%{passwords: " Foo,bar,foo , BAR "})
    assert config.passwords == ["foo", "bar"]
  end

  test "derives ipv4 and ipv6 subnets" do
    assert IpAccessAuth.subnet_for_ip({187, 180, 254, 75}) == {:ok, "187.180.254.0/24"}
    assert IpAccessAuth.subnet_for_ip("2001:db8:abcd:1234::1") == {:ok, "2001:db8:abcd::/48"}
  end

  test "records each successful authorization in the database" do
    config = %{passwords: "door", auth_path: "/auth"}

    assert {:ok, %{subnet: "203.0.113.0/24"}} =
             IpAccessAuth.authorize({203, 0, 113, 9}, "door", config)

    assert {:ok, %{subnet: "203.0.113.0/24"}} =
             IpAccessAuth.authorize({203, 0, 113, 9}, "door", config)

    entries =
      Repo.all(from entry in IpAccessEntry, order_by: [asc: entry.granted_at, asc: entry.ip])

    assert length(entries) == 2
    assert Enum.all?(entries, &(&1.ip == "203.0.113.0/24"))
    assert Enum.all?(entries, &(&1.password == "door"))
  end

  test "uses supplied password list" do
    assert {:ok, %{subnet: "203.0.113.0/24"}} =
             IpAccessAuth.authorize({203, 0, 113, 9}, "dbpass", %{passwords: ["dbpass"]})

    assert {:error, :invalid_password} =
             IpAccessAuth.authorize({203, 0, 113, 9}, "configonly", %{passwords: ["dbpass"]})
  end
end
