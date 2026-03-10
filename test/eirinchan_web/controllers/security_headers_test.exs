defmodule EirinchanWeb.SecurityHeadersTest do
  use EirinchanWeb.ConnCase, async: false

  test "browser responses include hardened security headers", %{conn: conn} do
    conn = get(conn, "/search", %{"q" => ""})

    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert get_resp_header(conn, "permissions-policy") == ["camera=(), microphone=(), geolocation=()"]
  end

  test "api responses include hardened security headers", %{conn: conn} do
    conn = get(conn, "/api/boards.json")

    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert get_resp_header(conn, "permissions-policy") == ["camera=(), microphone=(), geolocation=()"]
  end
end
