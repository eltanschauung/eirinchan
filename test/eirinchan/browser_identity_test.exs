defmodule Eirinchan.BrowserIdentityTest do
  use ExUnit.Case, async: true

  alias Eirinchan.BrowserIdentity

  test "issues and verifies a canonical signed identity" do
    token = BrowserIdentity.generate_token()
    encoded = BrowserIdentity.issue(token, 1_700_000_000)

    assert {:ok, %{token: ^token, issued_at: 1_700_000_000}} =
             BrowserIdentity.verify(encoded, 1_700_000_001)
  end

  test "rejects tampering, arbitrary strings, and future issuance" do
    token = BrowserIdentity.generate_token()
    encoded = BrowserIdentity.issue(token, 1_700_000_000)

    assert :error = BrowserIdentity.verify(encoded <> "x", 1_700_000_001)
    assert :error = BrowserIdentity.verify("attacker-chosen-token", 1_700_000_001)

    assert :error =
             BrowserIdentity.verify(BrowserIdentity.issue(token, 1_700_001_000), 1_700_000_000)
  end

  test "derives an idempotent, non-reversible storage reference" do
    token = BrowserIdentity.generate_token()
    reference = BrowserIdentity.reference(token)

    assert BrowserIdentity.reference?(reference)
    assert BrowserIdentity.reference(reference) == reference
    refute String.contains?(reference, token)
    refute BrowserIdentity.reference?(token)
  end

  test "derives a non-reversible IP and browser pair key" do
    reference = BrowserIdentity.reference("browser")
    client_key = BrowserIdentity.client_reference("198.51.100.44", reference)

    refute String.contains?(client_key, "198.51.100.44")
    refute String.contains?(client_key, reference)
    assert client_key == BrowserIdentity.client_reference("198.51.100.44", reference)
    refute client_key == BrowserIdentity.client_reference("198.51.100.45", reference)
  end
end
