defmodule EirinchanWeb.Plugs.TrackBrowserPresenceTest do
  use EirinchanWeb.ConnCase, async: false

  alias EirinchanWeb.Plugs.TrackBrowserPresence
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.VisitorQualification

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
    :ets.delete_all_objects(VisitorQualification.identity_table())
    :ets.delete_all_objects(VisitorQualification.bucket_table())
    :ok
  end

  test "tracks GET requests outside /manage", %{conn: conn} do
    browser_ref = BrowserIdentity.reference("presence-browser")

    conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.assign(:browser_ref, browser_ref)
      |> Plug.Conn.assign(:returning_browser_identity, true)
      |> TrackBrowserPresence.call([])

    assert conn.assigns.browser_ref == browser_ref
    assert [{^browser_ref, _seen_at}] = :ets.lookup(:eirinchan_browser_presence, browser_ref)
  end

  test "skips /manage requests", %{conn: conn} do
    browser_ref = BrowserIdentity.reference("manage-browser")

    _conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/manage")
      |> Plug.Conn.assign(:browser_ref, browser_ref)
      |> Plug.Conn.assign(:returning_browser_identity, true)
      |> TrackBrowserPresence.call([])

    assert [] == :ets.lookup(:eirinchan_browser_presence, browser_ref)
  end

  test "skips crawler user agents", %{conn: conn} do
    browser_ref = BrowserIdentity.reference("crawler-browser")

    _conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.put_req_header(
        "user-agent",
        "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
      )
      |> Plug.Conn.assign(:browser_ref, browser_ref)
      |> Plug.Conn.assign(:returning_browser_identity, true)
      |> TrackBrowserPresence.call([])

    assert [] == :ets.lookup(:eirinchan_browser_presence, browser_ref)
  end

  test "skips a newly issued identity until the browser returns it", %{conn: conn} do
    browser_ref = BrowserIdentity.reference("new-browser")
    issued_at = System.system_time(:second)

    _conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.assign(:browser_ref, browser_ref)
      |> Plug.Conn.assign(:browser_identity_issued_at, issued_at)
      |> Plug.Conn.assign(:returning_browser_identity, false)
      |> TrackBrowserPresence.call(now: issued_at)

    assert [] == :ets.lookup(:eirinchan_browser_presence, browser_ref)

    assert [{^browser_ref, _bucket, ^issued_at, :pending}] =
             :ets.lookup(VisitorQualification.identity_table(), browser_ref)
  end

  test "qualifies a returning identity only after the configured minimum age", %{conn: conn} do
    browser_ref = BrowserIdentity.reference("aged-browser")
    issued_at = System.system_time(:second)

    config = %{
      visitor_minimum_age_seconds: 60,
      visitor_identity_churn_limit: 3,
      visitor_identity_churn_window_seconds: 600
    }

    base_conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.put_req_header("user-agent", "Mozilla/5.0")
      |> Plug.Conn.assign(:browser_ref, browser_ref)
      |> Plug.Conn.assign(:browser_identity_issued_at, issued_at)

    _new_conn =
      base_conn
      |> Plug.Conn.assign(:returning_browser_identity, false)
      |> TrackBrowserPresence.call(now: issued_at, config: config)

    _early_conn =
      base_conn
      |> Plug.Conn.assign(:returning_browser_identity, true)
      |> TrackBrowserPresence.call(now: issued_at + 59, config: config)

    assert [] == :ets.lookup(:eirinchan_browser_presence, browser_ref)

    _qualified_conn =
      base_conn
      |> Plug.Conn.assign(:returning_browser_identity, true)
      |> TrackBrowserPresence.call(now: issued_at + 60, config: config)

    assert [{^browser_ref, _seen_at}] = :ets.lookup(:eirinchan_browser_presence, browser_ref)
  end
end
