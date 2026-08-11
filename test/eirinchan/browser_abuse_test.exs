defmodule Eirinchan.BrowserAbuseTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.Bans
  alias Eirinchan.BrowserAbuse
  alias Eirinchan.BrowserAbuse.Signal
  alias Eirinchan.BrowserIdentity

  test "uses a browser signal for temporary challenge escalation without creating a ban" do
    board = board_fixture()
    now = ~U[2026-07-13 12:00:00Z]
    browser_ref = BrowserIdentity.reference("browser-risk-signal")
    request = %{browser_ref: browser_ref, client_key: "client-ref:v1:test"}

    assert {:ok, _signal} =
             BrowserAbuse.record(request, :rate_limit, repo: Repo, now: now, ttl_seconds: 60)

    captcha_config = %{
      captcha: %{
        enabled: true,
        provider: "native",
        expected_response: "ok",
        mode: "none"
      }
    }

    assert BrowserAbuse.signaled?(request, repo: Repo, now: now)
    assert BrowserAbuse.challenge_required?(request, captcha_config, repo: Repo, now: now)
    refute Bans.active_ban_for_request(board, {198, 51, 100, 44}, repo: Repo)

    assert BrowserAbuse.prune_expired(repo: Repo, now: DateTime.add(now, 61, :second)) == 1
    refute BrowserAbuse.signaled?(request, repo: Repo, now: DateTime.add(now, 61, :second))
  end

  test "does not challenge when no usable captcha is configured" do
    request = %{browser_ref: BrowserIdentity.reference("browser-no-captcha")}
    assert {:ok, _signal} = BrowserAbuse.record(request, :rate_limit, repo: Repo)

    refute BrowserAbuse.challenge_required?(request, %{captcha: %{enabled: false}}, repo: Repo)

    refute BrowserAbuse.challenge_required?(
             request,
             %{captcha: %{enabled: true, provider: "native", expected_response: nil}},
             repo: Repo
           )
  end

  test "an older concurrent signal cannot shorten a newer signal" do
    browser_ref = BrowserIdentity.reference("browser-signal-high-water")
    request = %{browser_ref: browser_ref, client_key: "client-ref:v1:newer"}
    older_now = ~U[2026-07-13 12:00:00Z]
    newer_now = DateTime.add(older_now, 30, :second)

    assert {:ok, _signal} =
             BrowserAbuse.record(request, :newer, repo: Repo, now: newer_now, ttl_seconds: 120)

    assert {:ok, _signal} =
             BrowserAbuse.record(
               %{request | client_key: "client-ref:v1:older"},
               :older,
               repo: Repo,
               now: older_now,
               ttl_seconds: 60
             )

    signal = Repo.get!(Signal, browser_ref)
    assert signal.reason == "newer"
    assert signal.client_key == "client-ref:v1:newer"
    assert signal.expires_at == DateTime.add(newer_now, 120, :second)
  end
end
