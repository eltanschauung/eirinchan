defmodule EirinchanWeb.CsrfControllerTest do
  use EirinchanWeb.ConnCase, async: true

  test "GET /csrf-token returns a fresh token for the current session", %{conn: conn} do
    conn = get(conn, "/csrf-token")

    assert %{"csrf_token" => token} = json_response(conn, 200)
    assert is_binary(token)
    assert token != ""
  end
end
