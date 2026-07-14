defmodule Eirinchan.IpCloaksTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.IpCloaks

  test "issues opaque 16-character aliases and resolves their authenticated payloads" do
    payload = "Cloak:v2:authenticated-payload"

    assert {:ok, token} = IpCloaks.issue(payload)
    assert byte_size(token) == 16
    assert String.starts_with?(token, "c2_")
    assert IpCloaks.short_token?(token)
    assert IpCloaks.resolve(token) == payload

    refute IpCloaks.short_token?(token <> "x")
    assert IpCloaks.resolve("c2_invalid-token") == nil
  end

  test "expired aliases stop resolving and are pruned" do
    now = ~U[2026-07-14 12:00:00.000000Z]
    payload = "Cloak:v2:expiring-payload"

    assert {:ok, token} = IpCloaks.issue(payload, now: now, ttl_seconds: 60)
    assert IpCloaks.resolve(token, now: DateTime.add(now, 59, :second)) == payload
    assert IpCloaks.resolve(token, now: DateTime.add(now, 60, :second)) == nil
    assert IpCloaks.prune_expired(now: DateTime.add(now, 60, :second)) == 1
  end
end
