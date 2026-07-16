defmodule EirinchanWeb.SecurityHeadersTest do
  use EirinchanWeb.ConnCase, async: false

  test "browser responses include hardened security headers", %{conn: conn} do
    conn = get(conn, "/search", %{"q" => ""})

    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "object-src 'none'"
    assert csp =~ "script-src 'self' blob: 'wasm-unsafe-eval'"
    refute csp =~ "script-src 'self' 'unsafe-inline'"
    assert [permissions] = get_resp_header(conn, "permissions-policy")
    assert permissions =~ "camera=()"
    assert permissions =~ "microphone=()"
    assert permissions =~ "geolocation=()"
  end

  test "api responses include hardened security headers", %{conn: conn} do
    conn = get(conn, "/api/boards.json")

    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert [_csp] = get_resp_header(conn, "content-security-policy")
    assert [permissions] = get_resp_header(conn, "permissions-policy")
    assert permissions =~ "camera=()"
    assert permissions =~ "microphone=()"
    assert permissions =~ "geolocation=()"
  end
end
