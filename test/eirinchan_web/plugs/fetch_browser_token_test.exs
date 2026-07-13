defmodule EirinchanWeb.Plugs.FetchBrowserTokenTest do
  use EirinchanWeb.ConnCase, async: true

  alias EirinchanWeb.Plugs.FetchBrowserToken

  @cookie_name "__Host-eirinchan_browser"

  test "reuses existing host-only browser token cookie", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie(@cookie_name, "token-1234567890123456")
      |> FetchBrowserToken.call([])

    assert conn.assigns.browser_token == "token-1234567890123456"
    assert conn.assigns.returning_browser_token
  end

  test "creates browser token cookie when missing", %{conn: conn} do
    conn = FetchBrowserToken.call(conn, [])

    assert is_binary(conn.assigns.browser_token)
    assert byte_size(conn.assigns.browser_token) >= 16
    refute conn.assigns.returning_browser_token

    set_cookie =
      conn.resp_cookies
      |> Map.fetch!(@cookie_name)

    assert set_cookie.value == conn.assigns.browser_token
    assert set_cookie.path == "/"
    assert set_cookie.secure
    assert set_cookie.http_only
    assert set_cookie.same_site == "Lax"
  end

  test "migrates a legacy browser token without changing identity", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie("browser_token", "token-1234567890123456")
      |> FetchBrowserToken.call([])

    assert conn.assigns.browser_token == "token-1234567890123456"
    assert conn.assigns.returning_browser_token
    assert conn.resp_cookies[@cookie_name].value == "token-1234567890123456"
    assert conn.resp_cookies["browser_token"].max_age == 0
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
end
