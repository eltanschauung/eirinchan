defmodule Eirinchan.DNSBLTest do
  use ExUnit.Case, async: true

  alias Eirinchan.DNSBL

  test "skips local and exception IPs" do
    assert :ok = DNSBL.check({127, 0, 0, 1}, %{dnsbl: ["rbl.example"]})

    assert :ok =
             DNSBL.check(
               {203, 0, 113, 9},
               %{dnsbl: ["rbl.example"], dnsbl_exceptions: ["203.0.113.9"]}
             )
  end

  test "blocks matching single-octet responses" do
    resolver = fn "9.113.0.203.rbl.example" -> "127.0.0.4" end

    assert {:error, "rbl.example"} =
             DNSBL.check({203, 0, 113, 9}, %{dnsbl: [["rbl.example", 4]]}, resolver: resolver)
  end

  test "blocks matching array expectations and custom display names" do
    resolver = fn "9.113.0.203.key.dnsbl.example" -> "127.0.0.6" end

    assert {:error, "dnsbl.example"} =
             DNSBL.check(
               {203, 0, 113, 9},
               %{dnsbl: [["%.key.dnsbl.example", [5, 6], "dnsbl.example"]]},
               resolver: resolver
             )
  end

  test "blocks httpbl-style map expectations" do
    resolver = fn "9.113.0.203.key.dnsbl.httpbl.org" -> "127.10.7.4" end

    assert {:error, "dnsbl.httpbl.org"} =
             DNSBL.check(
               {203, 0, 113, 9},
               %{
                 dnsbl: [
                   %{
                     lookup: "%.key.dnsbl.httpbl.org",
                     expectation: %{type: "httpbl", max_days: 14, min_threat: 5},
                     display_name: "dnsbl.httpbl.org"
                   }
                 ]
               },
               resolver: resolver
             )
  end

  test "skips malformed blacklist entries without breaking later checks" do
    resolver = fn "9.113.0.203.valid.example" -> "127.0.0.4" end

    assert {:error, "valid.example"} =
             DNSBL.check(
               {203, 0, 113, 9},
               %{
                 dnsbl: [
                   nil,
                   %{"expectation" => 4},
                   [123, 4],
                   ["\r\ninvalid.example", 4],
                   ["valid.example", 4]
                 ]
               },
               resolver: resolver
             )
  end
end
