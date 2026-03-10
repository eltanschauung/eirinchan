defmodule EirinchanWeb.RequestMetaTest do
  use ExUnit.Case, async: true

  alias EirinchanWeb.RequestMeta
  import Plug.Conn
  import Plug.Test

  test "trusted_proxy? matches exact ips and cidr ranges" do
    assert RequestMeta.trusted_proxy?(
             {203, 0, 113, 10},
             %{trust_headers: true, trusted_ips: ["203.0.113.10"], trusted_cidrs: []}
           )

    assert RequestMeta.trusted_proxy?(
             {203, 0, 113, 44},
             %{trust_headers: true, trusted_ips: [], trusted_cidrs: ["203.0.113.0/24"]}
           )

    assert RequestMeta.trusted_proxy?(
             {0x2001, 0x0DB8, 0, 1, 0, 0, 0, 1},
             %{trust_headers: true, trusted_ips: [], trusted_cidrs: ["2001:db8:0:1::/64"]}
           )

    refute RequestMeta.trusted_proxy?(
             {198, 51, 100, 9},
             %{
               trust_headers: true,
               trusted_ips: ["203.0.113.10"],
               trusted_cidrs: ["203.0.113.0/24"]
             }
           )
  end

  test "effective_remote_ip uses forwarded client ip from trusted loopback proxy" do
    conn =
      :get
      |> conn("/")
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> put_req_header("x-forwarded-for", "198.51.100.44, 127.0.0.1")

    assert RequestMeta.effective_remote_ip(conn) == {198, 51, 100, 44}
    assert RequestMeta.forwarded_for(conn) == "198.51.100.44, 127.0.0.1"
  end
end
