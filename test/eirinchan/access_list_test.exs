defmodule Eirinchan.AccessListTest do
  use ExUnit.Case, async: false

  alias Eirinchan.AccessList

  setup do
    previous = Application.get_env(:eirinchan, :ip_access_list, %{enabled: false, entries: []})

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

  test "entries loads additional rules from a configurable access.conf path" do
    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-access-#{System.unique_integer([:positive])}.conf"
      )

    File.write!(path, """
    # comments are ignored
    198.51.100.7
    2001:db8:abcd::/48
    """)

    Application.put_env(:eirinchan, :ip_access_list, %{enabled: true, entries: [], path: path})

    assert "198.51.100.7" in AccessList.entries()
    assert "2001:db8:abcd::/48" in AccessList.entries()
    assert AccessList.allowed?({198, 51, 100, 7})
    assert AccessList.allowed?({0x2001, 0x0DB8, 0xABCD, 0x1, 0, 0, 0, 1})
    refute AccessList.allowed?({203, 0, 113, 9})
  end

  test "ip_matches_access_list accepts an access.conf path directly" do
    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-access-direct-#{System.unique_integer([:positive])}.conf"
      )

    File.write!(path, """
    198.51.100.0/24
    """)

    assert AccessList.ip_matches_access_list({198, 51, 100, 7}, path)
    refute AccessList.ip_matches_access_list({203, 0, 113, 9}, path)
  end
end
