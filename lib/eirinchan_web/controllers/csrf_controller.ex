defmodule EirinchanWeb.CsrfController do
  use EirinchanWeb, :controller

  def show(conn, _params) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store, max-age=0")
      |> put_resp_header("pragma", "no-cache")

    json(conn, %{csrf_token: get_csrf_token()})
  end
end
