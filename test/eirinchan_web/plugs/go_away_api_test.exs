defmodule EirinchanWeb.Plugs.GoAwayApiTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias EirinchanWeb.Plugs.GoAwayApi

  @statistics_path "/__goaway/api/statistics"
  @legacy_statistics_path "/__goaway/statistics"
  @ip_access_path "/__goaway/api/ipaccess"
  @legacy_ip_access_path "/__goaway/ipaccess"

  test "returns the private report with a default one-hour window" do
    test_pid = self()

    conn =
      @statistics_path
      |> private_conn()
      |> GoAwayApi.call(
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

  test "keeps the original statistics path as a compatibility alias" do
    conn =
      @legacy_statistics_path
      |> private_conn()
      |> GoAwayApi.call(report_fetcher: &%{hours: &1})

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["hours"] == 1
  end

  test "accepts a bounded hours query" do
    conn =
      private_conn(@statistics_path <> "?hours=24", "localhost")
      |> GoAwayApi.call(report_fetcher: &%{hours: &1})

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["hours"] == 24
  end

  test "rejects unbounded or malformed timeframes without running a query" do
    conn =
      private_conn(@statistics_path <> "?hours=999999", "::1", {0, 0, 0, 0, 0, 0, 0, 1})
      |> GoAwayApi.call(report_fetcher: fn _hours -> flunk("unexpected query") end)

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body)["error"] =~ "1 through 168"
  end

  test "returns no-content when the forwarded client has IP access" do
    test_pid = self()

    conn =
      @ip_access_path
      |> private_conn()
      |> put_req_header("x-forwarded-for", "198.51.100.44")
      |> GoAwayApi.call(
        allowed?: fn ip ->
          send(test_pid, {:checked_ip, ip})
          true
        end
      )

    assert conn.halted
    assert conn.status == 204
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert_received {:checked_ip, {198, 51, 100, 44}}
  end

  test "returns forbidden when the forwarded client lacks IP access" do
    conn =
      @ip_access_path
      |> private_conn("localhost")
      |> put_req_header("x-forwarded-for", "203.0.113.9")
      |> GoAwayApi.call(allowed?: fn _ip -> false end)

    assert conn.status == 403
  end

  test "fails closed without crashing when the IP access lookup is unavailable" do
    conn =
      @ip_access_path
      |> private_conn()
      |> GoAwayApi.call(allowed?: fn _ip -> raise "database unavailable" end)

    assert conn.halted
    assert conn.status == 503
    assert conn.resp_body == ""
  end

  test "does not retain the standalone IP access endpoint" do
    conn =
      @legacy_ip_access_path
      |> private_conn()
      |> GoAwayApi.call(allowed?: fn _ip -> flunk("unexpected lookup") end)

    refute conn.halted
    assert is_nil(conn.status)
  end

  test "does not expose either API operation through a public host" do
    for path <- [@statistics_path, @ip_access_path] do
      conn =
        path
        |> private_conn("bantculture.com")
        |> GoAwayApi.call(
          report_fetcher: fn _hours -> flunk("unexpected report") end,
          allowed?: fn _ip -> flunk("unexpected lookup") end
        )

      refute conn.halted
      assert is_nil(conn.status)
    end
  end

  test "does not trust direct non-loopback callers" do
    for path <- [@statistics_path, @ip_access_path] do
      conn =
        path
        |> private_conn("127.0.0.1", {192, 0, 2, 10})
        |> GoAwayApi.call(
          report_fetcher: fn _hours -> flunk("unexpected report") end,
          allowed?: fn _ip -> flunk("unexpected lookup") end
        )

      refute conn.halted
      assert is_nil(conn.status)
    end
  end

  defp private_conn(path, host \\ "127.0.0.1", remote_ip \\ {127, 0, 0, 1}) do
    :get
    |> conn(path)
    |> Map.put(:host, host)
    |> Map.put(:remote_ip, remote_ip)
  end
end
