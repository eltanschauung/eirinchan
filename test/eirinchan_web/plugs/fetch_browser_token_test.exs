defmodule EirinchanWeb.Plugs.FetchBrowserTokenTest do
  use EirinchanWeb.ConnCase, async: true

  alias EirinchanWeb.Plugs.FetchBrowserToken

  @cookie_name "__Host-eirinchan_browser"

  test "reuses existing host-only browser token cookie", %{conn: conn} do
    token = browser_token("existing")

    conn =
      conn
      |> put_req_cookie(@cookie_name, Eirinchan.BrowserIdentity.issue(token))
      |> FetchBrowserToken.call([])

    assert conn.assigns.browser_token == token
    assert conn.assigns.returning_browser_token
    refute Map.has_key?(conn.resp_cookies, @cookie_name)
  end

  test "creates browser token cookie when missing", %{conn: conn} do
    conn = FetchBrowserToken.call(conn, [])

    assert is_binary(conn.assigns.browser_token)
    assert byte_size(conn.assigns.browser_token) >= 16
    refute conn.assigns.returning_browser_token

    set_cookie =
      conn.resp_cookies
      |> Map.fetch!(@cookie_name)

    assert {:ok, %{token: token}} = Eirinchan.BrowserIdentity.verify(set_cookie.value)
    assert token == conn.assigns.browser_token
    assert set_cookie.path == "/"
    assert set_cookie.secure
    assert set_cookie.http_only
    assert set_cookie.same_site == "Lax"
  end

  test "migrates a legacy browser token without changing identity", %{conn: conn} do
    token = browser_token("legacy")

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> FetchBrowserToken.call([])

    assert conn.assigns.browser_token == token
    assert conn.assigns.returning_browser_token

    assert {:ok, %{token: ^token}} =
             Eirinchan.BrowserIdentity.verify(conn.resp_cookies[@cookie_name].value)

    assert conn.resp_cookies["browser_token"].max_age == 0
  end

  test "upgrades an unsigned host-only token", %{conn: conn} do
    token = browser_token("unsigned-host")

    conn = conn |> put_req_cookie(@cookie_name, token) |> FetchBrowserToken.call([])

    assert conn.assigns.browser_token == token
    assert conn.assigns.returning_browser_token

    assert {:ok, %{token: ^token}} =
             Eirinchan.BrowserIdentity.verify(conn.resp_cookies[@cookie_name].value)
  end

  test "rotates oversized attacker-controlled browser tokens", %{conn: conn} do
    oversized = String.duplicate("a", 129)

    conn =
      conn
      |> put_req_cookie(@cookie_name, oversized)
      |> FetchBrowserToken.call([])

    refute conn.assigns.browser_token == oversized
    refute conn.assigns.returning_browser_token
  end

  test "rotates noncanonical attacker-controlled browser tokens", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie(@cookie_name, "attacker-chosen-token")
      |> FetchBrowserToken.call([])

    refute conn.assigns.browser_token == "attacker-chosen-token"
    refute conn.assigns.returning_browser_token
  end
end
