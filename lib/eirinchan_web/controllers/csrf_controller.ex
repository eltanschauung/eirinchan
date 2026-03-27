defmodule EirinchanWeb.CsrfController do
  use EirinchanWeb, :controller

  def show(conn, _params) do
    json(conn, %{csrf_token: get_csrf_token()})
  end
end
