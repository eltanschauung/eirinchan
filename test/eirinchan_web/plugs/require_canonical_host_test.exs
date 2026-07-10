defmodule EirinchanWeb.Plugs.RequireCanonicalHostTest do
  use EirinchanWeb.ConnCase, async: true

  test "allows configured hosts", %{conn: conn} do
    assert conn |> get("/api/boards.json") |> response(200)
  end

  test "rejects attacker-controlled host headers before routing", %{conn: conn} do
    conn = conn |> Map.put(:host, "attacker.example") |> get("/api/boards.json")

    assert response(conn, 421) == "Misdirected Request"
  end
end
