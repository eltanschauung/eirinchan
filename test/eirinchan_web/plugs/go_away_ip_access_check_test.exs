defmodule EirinchanWeb.Plugs.GoAwayIpAccessCheckTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias EirinchanWeb.Plugs.GoAwayIpAccessCheck

  @path "/__goaway/ipaccess"

  test "returns no-content when the forwarded client is allowed" do
    test_pid = self()

    conn =
      :get
      |> conn(@path)
      |> Map.put(:host, "127.0.0.1")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> put_req_header("x-forwarded-for", "198.51.100.44")
      |> GoAwayIpAccessCheck.call(
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

  test "returns forbidden when the forwarded client is not allowed" do
    conn =
      :get
      |> conn(@path)
      |> Map.put(:host, "localhost")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> put_req_header("x-forwarded-for", "203.0.113.9")
      |> GoAwayIpAccessCheck.call(allowed?: fn _ip -> false end)

    assert conn.halted
    assert conn.status == 403
  end

  test "does not expose the decision endpoint through a public host" do
    conn =
      :get
      |> conn(@path)
      |> Map.put(:host, "bantculture.com")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> GoAwayIpAccessCheck.call(allowed?: fn _ip -> true end)

    refute conn.halted
    assert is_nil(conn.status)
  end

  test "does not trust direct non-loopback callers" do
    conn =
      :get
      |> conn(@path)
      |> Map.put(:host, "127.0.0.1")
      |> Map.put(:remote_ip, {203, 0, 113, 9})
      |> GoAwayIpAccessCheck.call(allowed?: fn _ip -> true end)

    refute conn.halted
    assert is_nil(conn.status)
  end
end
