defmodule Eirinchan.AccessListTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.AccessList
  alias Eirinchan.IpAccessEntry

  setup do
    previous = Application.get_env(:eirinchan, :ip_access_list, %{enabled: false, entries: []})
    Repo.delete_all(IpAccessEntry)

    on_exit(fn ->
      Application.put_env(:eirinchan, :ip_access_list, previous)
    end)

    :ok
  end

  test "ip_matches_access_list supports single ips and cidr ranges" do
    assert AccessList.ip_matches_access_list?({198, 51, 100, 7}, ["198.51.100.7"])
    assert AccessList.ip_matches_access_list?({198, 51, 100, 7}, ["198.51.100.0/24"])

    assert AccessList.ip_matches_access_list?(
             {0x2001, 0x0DB8, 0xABCD, 0x1, 0, 0, 0, 1},
             ["2001:db8:abcd::/48"]
           )

    refute AccessList.ip_matches_access_list?({198, 51, 100, 7}, ["203.0.113.0/24"])
  end

  test "entries loads inline rules plus stored database entries" do
    Application.put_env(:eirinchan, :ip_access_list, %{enabled: true, entries: ["198.51.100.7"]})

    Repo.insert!(%IpAccessEntry{
      ip: "2001:db8:abcd::/48",
      granted_at: NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second)
    })

    assert "198.51.100.7" in AccessList.entries()
    assert "2001:db8:abcd::/48" in AccessList.entries()
    assert AccessList.allowed?({198, 51, 100, 7})
    assert AccessList.allowed?({0x2001, 0x0DB8, 0xABCD, 0x1, 0, 0, 0, 1})
    refute AccessList.allowed?({203, 0, 113, 9})
  end

  test "allowed_for_posting uses stored database entries" do
    Repo.insert!(%IpAccessEntry{
      ip: "198.51.100.0/24",
      granted_at: NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second)
    })

    assert AccessList.allowed_for_posting?({198, 51, 100, 7})
    refute AccessList.allowed_for_posting?({203, 0, 113, 9})
  end

  test "most_recent_granted_at returns the newest matching grant timestamp" do
    now = NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second)
    older = NaiveDateTime.add(now, -60, :second)
    Repo.insert!(%IpAccessEntry{ip: "198.51.100.0/24", granted_at: older})
    Repo.insert!(%IpAccessEntry{ip: "198.51.100.55", granted_at: now})
    Repo.insert!(%IpAccessEntry{ip: "203.0.113.0/24", granted_at: now})

    assert AccessList.most_recent_granted_at({198, 51, 100, 55}) == now
    assert AccessList.most_recent_granted_at({192, 0, 2, 1}) == nil
  end

  test "expired grants are excluded and pruned" do
    now = NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second)
    expired = NaiveDateTime.add(now, -(8 * 24 * 60 * 60), :second)
    Repo.insert!(%IpAccessEntry{ip: "198.51.100.0/24", granted_at: expired})

    refute AccessList.allowed_for_posting?({198, 51, 100, 7})
    assert {1, nil} = AccessList.prune_expired(168, now)
    assert Repo.aggregate(IpAccessEntry, :count) == 0
  end

  test "import_legacy_file imports subnet rows with password and timestamp when present" do
    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-access-import-#{System.unique_integer([:positive])}.conf"
      )

    File.write!(path, """
    198.51.100.0/24
    #door 2026-03-25 18:05:16 198.51.100.9
    203.0.113.0/24
    """)

    assert {:ok, 2} = AccessList.import_legacy_file(path)

    entries = Repo.all(from entry in IpAccessEntry, order_by: entry.ip)

    assert Enum.map(entries, & &1.ip) == ["198.51.100.0/24", "203.0.113.0/24"]
    assert Eirinchan.CredentialHash.verify("door", Enum.at(entries, 0).password, :ip_access)
    refute Enum.at(entries, 0).password == "door"
    assert Enum.at(entries, 0).granted_at == ~N[2026-03-25 18:05:16]
    assert Enum.at(entries, 1).password == nil
    assert Enum.at(entries, 1).granted_at == nil
  end
end
