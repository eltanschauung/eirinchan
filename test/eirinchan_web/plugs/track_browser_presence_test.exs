defmodule EirinchanWeb.Plugs.TrackBrowserPresenceTest do
  use EirinchanWeb.ConnCase, async: false

  alias EirinchanWeb.Plugs.TrackBrowserPresence

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
    :ok
  end

  test "tracks GET requests outside /manage", %{conn: conn} do
    conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.assign(:browser_token, "token-1234567890123456")
      |> Plug.Conn.assign(:returning_browser_token, true)
      |> TrackBrowserPresence.call([])

    assert conn.assigns.browser_token == "token-1234567890123456"
    assert [{"token-1234567890123456", _seen_at}] = :ets.lookup(:eirinchan_browser_presence, "token-1234567890123456")
  end

  test "skips /manage requests", %{conn: conn} do
    _conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/manage")
      |> Plug.Conn.assign(:browser_token, "token-1234567890123456")
      |> Plug.Conn.assign(:returning_browser_token, true)
      |> TrackBrowserPresence.call([])

    assert [] == :ets.lookup(:eirinchan_browser_presence, "token-1234567890123456")
  end

  test "skips crawler user agents", %{conn: conn} do
    _conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.put_req_header("user-agent", "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)")
      |> Plug.Conn.assign(:browser_token, "token-1234567890123456")
      |> Plug.Conn.assign(:returning_browser_token, true)
      |> TrackBrowserPresence.call([])

    assert [] == :ets.lookup(:eirinchan_browser_presence, "token-1234567890123456")
  end

  test "skips a newly issued identity until the browser returns it", %{conn: conn} do
    _conn =
      conn
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.assign(:browser_token, "token-new-123456789012")
      |> Plug.Conn.assign(:returning_browser_token, false)
      |> TrackBrowserPresence.call([])

    assert [] == :ets.lookup(:eirinchan_browser_presence, "token-new-123456789012")
  end
end
