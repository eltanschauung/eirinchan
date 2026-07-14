defmodule Eirinchan.IpCryptTest do
  use Eirinchan.DataCase, async: false

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
    ipv6_cloak = IpCrypt.cloak_ip("2001:db8:abcd::7")

    assert String.starts_with?(cloaked, "c2_")
    assert byte_size(cloaked) == 16
    assert String.starts_with?(ipv6_cloak, "c2_")
    assert byte_size(ipv6_cloak) == 16
    refute cloaked == "198.51.100.7"
    assert IpCrypt.uncloak_ip(cloaked) == "198.51.100.7"
    assert IpCrypt.uncloak_ip(ipv6_cloak) == "2001:db8:abcd::7"
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

  test "authenticated cloaks are stable per request, randomized across requests, and reject tampering" do
    IpCrypt.configure_for_request(%{ipcrypt_key: "test-key"}, "203.0.113.5")

    first = IpCrypt.cloak_ip("198.51.100.7")
    second = IpCrypt.cloak_ip("198.51.100.7")

    assert first == second
    assert IpCrypt.uncloak_ip(first) == "198.51.100.7"

    IpCrypt.configure_for_request(%{ipcrypt_key: "test-key"}, "203.0.113.5")
    refute IpCrypt.cloak_ip("198.51.100.7") == first

    "c2_" <> <<first_character>> <> rest = first
    replacement = if first_character == ?A, do: ?B, else: ?A
    tampered = "c2_" <> <<replacement>> <> rest
    assert IpCrypt.uncloak_ip(tampered) == nil
  end

  test "uncloak_ip remains compatible with full authenticated v2 cloaks" do
    key = "test-key"
    IpCrypt.configure_for_request(%{ipcrypt_key: key}, "203.0.113.5")
    full_cloak = authenticated_v2_cloak("198.51.100.7", key)

    assert String.starts_with?(full_cloak, "Cloak:v2:")
    assert IpCrypt.uncloak_ip(full_cloak) == "198.51.100.7"
  end

  test "uncloak_ip remains compatible with legacy ctr cloaks" do
    IpCrypt.configure_for_request(%{ipcrypt_key: "test-key"}, "203.0.113.5")

    plaintext = <<198, 51, 100, 7>>
    key = :crypto.hash(:sha256, "test-key")
    ciphertext = :crypto.crypto_one_time(:aes_256_ctr, key, <<0::128>>, plaintext, true)
    legacy = "Cloak:" <> Base.encode32(ciphertext, padding: false, case: :upper)

    assert IpCrypt.uncloak_ip(legacy) == "198.51.100.7"
  end

  defp authenticated_v2_cloak(ip, key) do
    nonce = :crypto.strong_rand_bytes(12)
    plaintext = ip |> Eirinchan.IpMatching.normalize_ip() |> ip_to_binary()

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        :crypto.hash(:sha256, key),
        nonce,
        plaintext,
        "eirinchan-ipcrypt-v2",
        16,
        true
      )

    "Cloak:v2:" <> Base.url_encode64(nonce <> tag <> ciphertext, padding: false)
  end

  defp ip_to_binary({a, b, c, d}), do: <<a, b, c, d>>
end
