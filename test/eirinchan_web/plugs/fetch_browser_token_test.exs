defmodule EirinchanWeb.Plugs.FetchBrowserTokenTest do
  use EirinchanWeb.ConnCase, async: true

  alias EirinchanWeb.Plugs.FetchBrowserToken

  test "reuses existing browser token cookie", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie("browser_token", "token-1234567890123456")
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
      |> Map.fetch!("browser_token")

    assert set_cookie.value == conn.assigns.browser_token
    assert set_cookie.path == "/"
  end

  test "rotates oversized attacker-controlled browser tokens", %{conn: conn} do
    oversized = String.duplicate("a", 129)

    conn =
      conn
      |> put_req_cookie("browser_token", oversized)
      |> FetchBrowserToken.call([])

    refute conn.assigns.browser_token == oversized
    refute conn.assigns.returning_browser_token
  end
end
