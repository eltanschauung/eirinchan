defmodule EirinchanWeb.Plugs.FetchBrowserToken do
  import Plug.Conn

  @cookie_name "browser_token"
  @max_age 60 * 60 * 24 * 365 * 5

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = ensure_cookies(conn)

    case conn.cookies[@cookie_name] do
      token when is_binary(token) and byte_size(token) >= 16 ->
        assign(conn, :browser_token, token)

      _ ->
        token = generate_token()

        conn
        |> assign(:browser_token, token)
        |> put_resp_cookie(@cookie_name, token,
          max_age: @max_age,
          path: "/",
          http_only: true,
          secure: Mix.env() == :prod,
          same_site: "Lax"
        )
    end
  end

  defp ensure_cookies(%Plug.Conn{cookies: %Plug.Conn.Unfetched{}} = conn), do: fetch_cookies(conn)
  defp ensure_cookies(conn), do: conn

  def generate_token do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
