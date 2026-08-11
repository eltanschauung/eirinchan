defmodule EirinchanWeb.Plugs.TrackBrowserPresenceTest do
  use EirinchanWeb.ConnCase, async: false

  alias EirinchanWeb.Plugs.TrackBrowserPresence
  alias Eirinchan.BrowserIdentity

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
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

    _conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.assign(:browser_ref, browser_ref)
      |> Plug.Conn.assign(:returning_browser_identity, false)
      |> TrackBrowserPresence.call([])

    assert [] == :ets.lookup(:eirinchan_browser_presence, browser_ref)
  end
end
