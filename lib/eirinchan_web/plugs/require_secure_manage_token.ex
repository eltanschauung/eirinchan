defmodule EirinchanWeb.Plugs.RequireSecureManageToken do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = get_session(conn, :secure_manage_token)
    provided = List.first(get_req_header(conn, "x-secure-token"))

    if is_binary(expected) and expected != "" and
         Plug.Crypto.secure_compare(expected, provided || "") do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{error: "invalid_secure_token"})
      |> halt()
    end
  end
end
