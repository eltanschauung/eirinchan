defmodule Eirinchan.IpCryptTest do
  use ExUnit.Case, async: false

  alias Eirinchan.IpCrypt

  setup do
    IpCrypt.clear_request_context()

    on_exit(fn ->
      IpCrypt.clear_request_context()
    end)

    :ok
  end

  test "cloak_ip uses ipcrypt_key from request config" do
    IpCrypt.configure_for_request(%{ipcrypt_key: "test-key"}, "203.0.113.5")

    cloaked = IpCrypt.cloak_ip("198.51.100.7")

    assert cloaked =~ "Cloak:v2:"
    refute cloaked == "198.51.100.7"
    assert IpCrypt.uncloak_ip(cloaked) == "198.51.100.7"
  end

  test "ipcrypt_immune_ip lets matching viewers see raw ips" do
    IpCrypt.configure_for_request(
      %{ipcrypt_key: "test-key", ipcrypt_immune_ip: "198.51.100.0/24"},
      "198.51.100.44"
    )

    assert IpCrypt.cloak_ip("203.0.113.9") == "203.0.113.9"
  end

  test "non-immune viewers still see cloaked ips when immune range is configured" do
    IpCrypt.configure_for_request(
      %{ipcrypt_key: "test-key", ipcrypt_immune_ip: "198.51.100.0/24"},
      "203.0.113.44"
    )

    refute IpCrypt.cloak_ip("198.51.100.7") == "198.51.100.7"
  end

  test "uncloak_ip accepts already-plain valid ips" do
    IpCrypt.configure_for_request(%{ipcrypt_key: "test-key"}, "203.0.113.5")

    assert IpCrypt.uncloak_ip("198.51.100.7") == "198.51.100.7"
    assert IpCrypt.uncloak_ip("2001:db8:abcd::1") == "2001:db8:abcd::1"
    assert IpCrypt.uncloak_ip("Cloak:deadbeef") == nil
  end

  test "authenticated cloaks are randomized and reject tampering" do
    IpCrypt.configure_for_request(%{ipcrypt_key: "test-key"}, "203.0.113.5")

    first = IpCrypt.cloak_ip("198.51.100.7")
    second = IpCrypt.cloak_ip("198.51.100.7")

    refute first == second
    assert IpCrypt.uncloak_ip(first) == "198.51.100.7"

    "Cloak:v2:" <> <<first_character>> <> rest = first
    replacement = if first_character == ?A, do: ?B, else: ?A
    tampered = "Cloak:v2:" <> <<replacement>> <> rest
    assert IpCrypt.uncloak_ip(tampered) == nil
  end

  test "uncloak_ip remains compatible with legacy ctr cloaks" do
    IpCrypt.configure_for_request(%{ipcrypt_key: "test-key"}, "203.0.113.5")

    plaintext = <<198, 51, 100, 7>>
    key = :crypto.hash(:sha256, "test-key")
    ciphertext = :crypto.crypto_one_time(:aes_256_ctr, key, <<0::128>>, plaintext, true)
    legacy = "Cloak:" <> Base.encode32(ciphertext, padding: false, case: :upper)

    assert IpCrypt.uncloak_ip(legacy) == "198.51.100.7"
  end
end
