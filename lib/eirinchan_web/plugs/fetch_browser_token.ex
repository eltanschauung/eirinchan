defmodule EirinchanWeb.Plugs.FetchBrowserToken do
  import Plug.Conn

  @cookie_name "__Host-eirinchan_browser"
  @legacy_cookie_name "browser_token"
  @max_age 60 * 60 * 24 * 365 * 5

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = ensure_cookies(conn)

    case browser_token(conn.cookies) do
      {:current, token} ->
        conn
        |> assign(:browser_token, token)
        |> assign(:returning_browser_token, true)

      {:legacy, token} ->
        conn
        |> assign(:browser_token, token)
        |> assign(:returning_browser_token, true)
        |> put_browser_cookie(token)
        |> delete_resp_cookie(@legacy_cookie_name, path: "/")

      :missing ->
        token = generate_token()

        conn
        |> assign(:browser_token, token)
        |> assign(:returning_browser_token, false)
        |> put_browser_cookie(token)
    end
  end

  defp browser_token(cookies) do
    cond do
      valid_token?(cookies[@cookie_name]) -> {:current, cookies[@cookie_name]}
      valid_token?(cookies[@legacy_cookie_name]) -> {:legacy, cookies[@legacy_cookie_name]}
      true -> :missing
    end
  end

  defp valid_token?(token),
    do: is_binary(token) and byte_size(token) >= 16 and byte_size(token) <= 128

  defp put_browser_cookie(conn, token) do
    put_resp_cookie(conn, @cookie_name, token,
      max_age: @max_age,
      path: "/",
      http_only: true,
      secure: true,
      same_site: "Lax"
    )
  end

  defp ensure_cookies(%Plug.Conn{cookies: %Plug.Conn.Unfetched{}} = conn), do: fetch_cookies(conn)
  defp ensure_cookies(conn), do: conn

  def generate_token do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
