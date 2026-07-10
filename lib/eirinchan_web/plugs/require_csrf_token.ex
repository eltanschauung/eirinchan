defmodule EirinchanWeb.Plugs.RequireCsrfToken do
  @moduledoc false

  import Plug.Conn

  alias Plug.CSRFProtection

  def init(opts), do: opts

  def call(conn, _opts) do
    state =
      conn
      |> get_session("_csrf_token")
      |> CSRFProtection.dump_state_from_session()

    token =
      conn
      |> get_req_header("x-csrf-token")
      |> List.first()
      |> case do
        nil -> Map.get(conn.body_params, "_csrf_token")
        value -> value
      end

    if CSRFProtection.valid_state_and_csrf_token?(state, token) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{
        csrf: true,
        error: "Your tab is out of date. Refreshing the CSRF token and retrying."
      })
      |> halt()
    end
  end
end
