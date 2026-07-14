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

  test "unknown configuration keys do not create atoms" do
    # Warm the module and atom-count machinery before taking the baseline.
    _ = IpAccessAuth.effective_config(%{"unknown-warmup" => true})
    _ = :erlang.system_info(:atom_count)
    before_count = :erlang.system_info(:atom_count)

    config =
      1..1_000
      |> Map.new(fn index -> {"attacker-key-#{index}", index} end)
      |> Map.put("auth-path", "/gate")
      |> IpAccessAuth.effective_config()

    assert config.auth_path == "/gate"
    assert :erlang.system_info(:atom_count) == before_count
  end

  test "derives ipv4 and ipv6 subnets" do
    assert IpAccessAuth.subnet_for_ip({187, 180, 254, 75}) == {:ok, "187.180.254.0/24"}
    assert IpAccessAuth.subnet_for_ip("2001:db8:abcd:1234::1") == {:ok, "2001:db8:abcd::/48"}
  end

  test "refreshes one expiring authorization per subnet" do
    config = %{passwords: "door", auth_path: "/auth"}

    assert {:ok, %{subnet: "203.0.113.0/24"}} =
             IpAccessAuth.authorize({203, 0, 113, 9}, "door", config)

    assert {:ok, %{subnet: "203.0.113.0/24"}} =
             IpAccessAuth.authorize({203, 0, 113, 9}, "door", config)

    entries =
      Repo.all(from entry in IpAccessEntry, order_by: [asc: entry.granted_at, asc: entry.ip])

    assert [%IpAccessEntry{} = entry] = entries
    assert entry.ip == "203.0.113.0/24"
    assert Eirinchan.CredentialHash.verify("door", entry.password, :ip_access)
    refute entry.password == "door"
  end

  test "uses supplied password list" do
    assert {:ok, %{subnet: "203.0.113.0/24"}} =
             IpAccessAuth.authorize({203, 0, 113, 9}, "dbpass", %{passwords: ["dbpass"]})

    assert {:error, :invalid_password} =
             IpAccessAuth.authorize({203, 0, 113, 9}, "configonly", %{passwords: ["dbpass"]})
  end

  test "accepts existing HMAC entries alongside newly stored plaintext entries" do
    encoded = Eirinchan.CredentialHash.hash("legacydoor", :ip_access)
    config = %{passwords: [encoded, "newdoor"]}

    assert {:ok, _grant} = IpAccessAuth.authorize({203, 0, 113, 10}, "LegacyDoor", config)
    assert {:ok, _grant} = IpAccessAuth.authorize({203, 0, 114, 10}, "NewDoor", config)

    assert {:error, :invalid_password} =
             IpAccessAuth.authorize({203, 0, 115, 10}, "wrong", config)
  end
end
