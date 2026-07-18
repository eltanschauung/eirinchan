defmodule EirinchanWeb.Plugs.GoAwayStatisticsTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias EirinchanWeb.Plugs.GoAwayStatistics

  @path "/__goaway/statistics"

  test "returns the private report with a default one-hour window" do
    test_pid = self()

    conn =
      :get
      |> conn(@path)
      |> Map.put(:host, "127.0.0.1")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> GoAwayStatistics.call(
        report_fetcher: fn hours ->
          send(test_pid, {:hours, hours})
          %{version: 1, timeframe_hours: hours}
        end
      )

    assert conn.halted
    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert Jason.decode!(conn.resp_body)["timeframe_hours"] == 1
    assert_received {:hours, 1}
  end

  test "accepts a bounded hours query" do
    conn =
      :get
      |> conn(@path <> "?hours=24")
      |> Map.put(:host, "localhost")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> GoAwayStatistics.call(report_fetcher: &%{hours: &1})

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["hours"] == 24
  end

  test "rejects unbounded or malformed timeframes without running a query" do
    conn =
      :get
      |> conn(@path <> "?hours=999999")
      |> Map.put(:host, "::1")
      |> Map.put(:remote_ip, {0, 0, 0, 0, 0, 0, 0, 1})
      |> GoAwayStatistics.call(report_fetcher: fn _hours -> flunk("unexpected query") end)

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body)["error"] =~ "1 through 168"
  end

  test "does not expose statistics through the public host" do
    conn =
      :get
      |> conn(@path)
      |> Map.put(:host, "example.test")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> GoAwayStatistics.call(report_fetcher: fn _hours -> flunk("unexpected query") end)

    refute conn.halted
    assert is_nil(conn.status)
  end

  test "does not trust non-loopback callers" do
    conn =
      :get
      |> conn(@path)
      |> Map.put(:host, "127.0.0.1")
      |> Map.put(:remote_ip, {192, 0, 2, 10})
      |> GoAwayStatistics.call(report_fetcher: fn _hours -> flunk("unexpected query") end)

    refute conn.halted
    assert is_nil(conn.status)
  end
end
