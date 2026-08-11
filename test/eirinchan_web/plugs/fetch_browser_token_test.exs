defmodule EirinchanWeb.Plugs.FetchBrowserTokenTest do
  use EirinchanWeb.ConnCase, async: true

  alias EirinchanWeb.Plugs.FetchBrowserToken
  alias Eirinchan.BrowserIdentities
  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.Repo

  @cookie_name "__Host-eirinchan_browser"

  test "reuses existing host-only browser token cookie", %{conn: conn} do
    token = browser_token("existing")

    conn =
      conn
      |> put_req_cookie(@cookie_name, BrowserIdentity.issue(token))
      |> FetchBrowserToken.call([])

    assert conn.assigns.browser_ref == BrowserIdentity.reference(token)
    refute Map.has_key?(conn.assigns, :browser_identity_token)
    assert conn.assigns.returning_browser_identity
    refute Map.has_key?(conn.resp_cookies, @cookie_name)
  end

  test "creates a browser token cookie without persisting an unreturned identity", %{conn: conn} do
    conn = FetchBrowserToken.call(conn, [])

    assert BrowserIdentity.reference?(conn.assigns.browser_ref)
    refute conn.assigns.returning_browser_identity

    set_cookie =
      conn.resp_cookies
      |> Map.fetch!(@cookie_name)

    assert {:ok, %{token: token}} = BrowserIdentity.verify(set_cookie.value)
    assert BrowserIdentity.reference(token) == conn.assigns.browser_ref
    refute Map.has_key?(conn.assigns, :browser_identity_token)
    refute Repo.get(Identity, conn.assigns.browser_ref)
    assert set_cookie.path == "/"
    assert set_cookie.secure
    assert set_cookie.http_only
    assert set_cookie.same_site == "Lax"
  end

  test "repeated cookie-less requests do not create database identities", %{conn: conn} do
    identity_count = Repo.aggregate(Identity, :count)

    for _attempt <- 1..5 do
      conn
      |> recycle()
      |> FetchBrowserToken.call([])
    end

    assert Repo.aggregate(Identity, :count) == identity_count
  end

  test "persists an identity only after the signed cookie returns", %{conn: conn} do
    first_conn = FetchBrowserToken.call(conn, [])
    signed_cookie = first_conn.resp_cookies[@cookie_name].value
    browser_ref = first_conn.assigns.browser_ref

    refute Repo.get(Identity, browser_ref)

    returning_conn =
      conn
      |> recycle()
      |> put_req_cookie(@cookie_name, signed_cookie)
      |> FetchBrowserToken.call([])

    assert returning_conn.assigns.returning_browser_identity
    assert returning_conn.assigns.browser_ref == browser_ref
    assert Repo.get(Identity, browser_ref)
  end

  test "migrates a legacy browser token without changing identity", %{conn: conn} do
    token = browser_token("legacy")

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> FetchBrowserToken.call([])

    assert conn.assigns.browser_ref == BrowserIdentity.reference(token)
    refute Map.has_key?(conn.assigns, :browser_identity_token)
    assert conn.assigns.returning_browser_identity

    assert {:ok, %{token: ^token}} =
             BrowserIdentity.verify(conn.resp_cookies[@cookie_name].value)

    assert conn.resp_cookies["browser_token"].max_age == 0
    assert conn.resp_cookies["browser_token"].secure
    assert conn.resp_cookies["browser_token"].same_site == "Lax"
  end

  test "upgrades an unsigned host-only token", %{conn: conn} do
    token = browser_token("unsigned-host")

    conn = conn |> put_req_cookie(@cookie_name, token) |> FetchBrowserToken.call([])

    assert conn.assigns.browser_ref == BrowserIdentity.reference(token)
    refute Map.has_key?(conn.assigns, :browser_identity_token)
    assert conn.assigns.returning_browser_identity

    assert {:ok, %{token: ^token}} =
             BrowserIdentity.verify(conn.resp_cookies[@cookie_name].value)
  end

  test "rotates oversized attacker-controlled browser tokens", %{conn: conn} do
    oversized = String.duplicate("a", 129)

    conn =
      conn
      |> put_req_cookie(@cookie_name, oversized)
      |> FetchBrowserToken.call([])

    refute conn.assigns.browser_ref == oversized
    refute conn.assigns.returning_browser_identity
  end

  test "rotates noncanonical attacker-controlled browser tokens", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie(@cookie_name, "attacker-chosen-token")
      |> FetchBrowserToken.call([])

    refute conn.assigns.browser_ref == "attacker-chosen-token"
    refute conn.assigns.returning_browser_identity
  end

  test "refreshes an aged signature without changing the storage identity", %{conn: conn} do
    token = browser_token("aged-signature")
    issued_at = System.system_time(:second) - BrowserIdentities.rotation_seconds()

    conn =
      conn
      |> put_req_cookie(@cookie_name, BrowserIdentity.issue(token, issued_at))
      |> FetchBrowserToken.call([])

    assert conn.assigns.browser_ref == BrowserIdentity.reference(token)
    assert conn.assigns.returning_browser_identity

    assert {:ok, %{token: ^token, issued_at: refreshed_at}} =
             BrowserIdentity.verify(conn.resp_cookies[@cookie_name].value)

    assert refreshed_at > issued_at
  end

  test "replaces a cookie beyond its absolute lifetime", %{conn: conn} do
    token = browser_token("expired-signature")
    issued_at = System.system_time(:second) - BrowserIdentities.ttl_seconds() - 1

    conn =
      conn
      |> put_req_cookie(@cookie_name, BrowserIdentity.issue(token, issued_at))
      |> FetchBrowserToken.call([])

    refute Map.has_key?(conn.assigns, :browser_identity_token)
    refute conn.assigns.returning_browser_identity
    assert BrowserIdentity.reference?(conn.assigns.browser_ref)
  end
end
