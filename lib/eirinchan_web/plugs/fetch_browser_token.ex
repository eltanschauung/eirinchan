defmodule EirinchanWeb.Plugs.FetchBrowserToken do
  import Plug.Conn

  alias Eirinchan.BrowserIdentities
  alias Eirinchan.BrowserIdentity

  @cookie_name "__Host-eirinchan_browser"
  @legacy_cookie_name "browser_token"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = ensure_cookies(conn)

    case browser_identity(conn.cookies) do
      {:current, token, issued_at} ->
        resolve_identity(conn, token, issued_at, true, false)

      {:upgrade, token} ->
        conn
        |> resolve_identity(token, System.system_time(:second), true, true)
        |> delete_resp_cookie(@legacy_cookie_name, path: "/")

      :missing ->
        issue_new_identity(conn)
    end
  end

  defp browser_identity(cookies) do
    case BrowserIdentity.verify(cookies[@cookie_name]) do
      {:ok, %{token: token, issued_at: issued_at}} ->
        {:current, token, issued_at}

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
      max_age: BrowserIdentities.ttl_seconds(),
      path: "/",
      http_only: true,
      secure: true,
      same_site: "Lax"
    )
  end

  defp assign_identity(conn, token) do
    conn
    |> assign(:browser_token, BrowserIdentity.reference(token))
    |> assign(:browser_identity_token, token)
  end

  defp resolve_identity(conn, token, issued_at, returning?, set_cookie?) do
    case BrowserIdentities.resolve(token, issued_at) do
      {:ok, _reference, options} ->
        conn
        |> assign_identity(token)
        |> assign(:returning_browser_token, returning?)
        |> maybe_refresh_cookie(token, set_cookie? or options[:rotate_cookie?])

      {:expired, _reference} ->
        issue_new_identity(conn)
    end
  end

  defp issue_new_identity(conn) do
    token = generate_token()
    issued_at = System.system_time(:second)
    {:ok, _reference, _options} = BrowserIdentities.resolve(token, issued_at)

    conn
    |> assign_identity(token)
    |> assign(:returning_browser_token, false)
    |> put_browser_cookie(BrowserIdentity.issue(token, issued_at))
  end

  defp maybe_refresh_cookie(conn, _token, false), do: conn

  defp maybe_refresh_cookie(conn, token, true) do
    put_browser_cookie(conn, BrowserIdentity.issue(token))
  end

  defp ensure_cookies(%Plug.Conn{cookies: %Plug.Conn.Unfetched{}} = conn), do: fetch_cookies(conn)
  defp ensure_cookies(conn), do: conn

  def generate_token do
    BrowserIdentity.generate_token()
  end
end
