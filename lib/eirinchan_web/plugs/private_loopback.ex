defmodule EirinchanWeb.Plugs.PrivateLoopback do
  @moduledoc false

  @loopback_hosts MapSet.new(["127.0.0.1", "localhost", "::1"])

  def request?(%Plug.Conn{} = conn) do
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
