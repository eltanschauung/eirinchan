defmodule EirinchanWeb.StaticSecurityHeadersTest do
  use EirinchanWeb.ConnCase, async: false

  test "static JavaScript receives nosniff before the router", %{conn: conn} do
    response = get(conn, "/js/auth-redirect.js?v=security-fixture")
    assert response.status == 200
    assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(response, "cache-control") == ["public, max-age=31536000, immutable"]
  end
end
