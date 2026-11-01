defmodule Eirinchan.IpMatchingTest do
  use ExUnit.Case, async: true

  alias Eirinchan.IpMatching

  test "normalizes ipv4-mapped ipv6 loopback to ipv4" do
    assert IpMatching.normalize_ip("::ffff:127.0.0.1") == {127, 0, 0, 1}
  end

  test "mapped IPv4 tuples match the same authentication subnet as IPv4" do
    assert IpMatching.ip_in_cidr?({0, 0, 0, 0, 0, 0xFFFF, 0xC000, 0x0205}, "192.0.2.0/24")
    refute IpMatching.ip_in_cidr?({0, 0, 0, 0, 0, 0xFFFF, 0xC000, 0x0205}, "198.51.100.0/24")
  end

  test "matches ipv4-mapped ipv6 against trusted localhost entries" do
    assert IpMatching.entry_match?("::ffff:127.0.0.1", "127.0.0.1")
    assert IpMatching.entry_match?("::ffff:127.0.0.1", "127.0.0.0/8")
  end
end
