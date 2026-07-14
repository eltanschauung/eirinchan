defmodule EirinchanWeb.Plugs.GoAwayIpAccessCheck do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.AccessList
  alias EirinchanWeb.RequestMeta

  @path "/__goaway/ipaccess"
  @loopback_hosts MapSet.new(["127.0.0.1", "localhost", "::1"])

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: @path} = conn, opts) do
    if loopback_request?(conn) do
      allowed? = Keyword.get(opts, :allowed?, &AccessList.allowed_for_posting?/1)
      remote_ip = RequestMeta.effective_remote_ip(conn)
      status = if allowed?.(remote_ip), do: 204, else: 403

      conn
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(status, "")
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp loopback_request?(conn) do
    MapSet.member?(@loopback_hosts, normalize_host(conn.host)) and loopback_ip?(conn.remote_ip)
  end

  defp normalize_host(host) do
    host
    |> to_string()
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.downcase()
  end

  defp loopback_ip?({127, _, _, _}), do: true
  defp loopback_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback_ip?({0, 0, 0, 0, 0, 65_535, 0x7F00, _}), do: true
  defp loopback_ip?(_), do: false
end
