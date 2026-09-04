defmodule EirinchanWeb.Plugs.FetchBrowserToken do
  import Plug.Conn

  alias Eirinchan.BrowserIdentities
  alias Eirinchan.BrowserIdentity
  alias EirinchanWeb.CookiePolicy

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
        |> resolve_identity(token, System.system_time(:second), true, true, nil)
        |> delete_resp_cookie(@legacy_cookie_name, CookiePolicy.browser_identity_delete())

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
    put_resp_cookie(
      conn,
      @cookie_name,
      token,
      CookiePolicy.browser_identity(BrowserIdentities.ttl_seconds())
    )
  end

  defp assign_identity(conn, token, issued_at) do
    conn
    |> assign(:browser_ref, BrowserIdentity.reference(token))
    |> assign(:browser_identity_issued_at, issued_at)
  end

  defp resolve_identity(conn, token, issued_at, returning?, set_cookie?) do
    resolve_identity(conn, token, issued_at, returning?, set_cookie?, issued_at)
  end

  defp resolve_identity(conn, token, issued_at, returning?, set_cookie?, qualification_issued_at) do
    case BrowserIdentities.resolve(token, issued_at) do
      {:ok, _reference, options} ->
        conn
        |> assign_identity(token, qualification_issued_at)
        |> assign(:returning_browser_identity, returning?)
        |> maybe_refresh_cookie(token, set_cookie? or options[:rotate_cookie?])

      {:expired, _reference} ->
        issue_new_identity(conn)
    end
  end

  defp issue_new_identity(conn) do
    token = generate_token()
    issued_at = System.system_time(:second)

    conn
    |> assign_identity(token, issued_at)
    |> assign(:returning_browser_identity, false)
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
