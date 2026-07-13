defmodule EirinchanWeb.Plugs.FetchBrowserToken do
  import Plug.Conn

  alias Eirinchan.BrowserIdentity

  @cookie_name "__Host-eirinchan_browser"
  @legacy_cookie_name "browser_token"
  @max_age 60 * 60 * 24 * 365 * 5

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = ensure_cookies(conn)

    case browser_identity(conn.cookies) do
      {:current, token} ->
        conn
        |> assign(:browser_token, token)
        |> assign(:returning_browser_token, true)

      {:upgrade, token} ->
        conn
        |> assign(:browser_token, token)
        |> assign(:returning_browser_token, true)
        |> put_browser_cookie(BrowserIdentity.issue(token))
        |> delete_resp_cookie(@legacy_cookie_name, path: "/")

      :missing ->
        token = generate_token()

        conn
        |> assign(:browser_token, token)
        |> assign(:returning_browser_token, false)
        |> put_browser_cookie(BrowserIdentity.issue(token))
    end
  end

  defp browser_identity(cookies) do
    case BrowserIdentity.verify(cookies[@cookie_name]) do
      {:ok, %{token: token}} ->
        {:current, token}

      :error ->
        cond do
          BrowserIdentity.valid_token?(cookies[@cookie_name]) ->
            {:upgrade, cookies[@cookie_name]}

          BrowserIdentity.valid_token?(cookies[@legacy_cookie_name]) ->
            {:upgrade, cookies[@legacy_cookie_name]}

          true ->
            :missing
        end
    end
  end

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
    BrowserIdentity.generate_token()
  end
end
