defmodule EirinchanWeb.CsrfControllerTest do
  use EirinchanWeb.ConnCase, async: true

  test "GET /csrf-token returns a fresh token for the current session", %{conn: conn} do
    conn = get(conn, "/csrf-token")

    assert %{"csrf_token" => token} = json_response(conn, 200)
    assert is_binary(token)
    assert token != ""
    assert get_resp_header(conn, "cache-control") == ["no-store, max-age=0"]
    assert get_resp_header(conn, "pragma") == ["no-cache"]
  end
end
