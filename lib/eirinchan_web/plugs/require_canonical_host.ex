defmodule EirinchanWeb.Plugs.RequireCanonicalHost do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    allowed_hosts =
      :eirinchan
      |> Application.get_env(:allowed_hosts, [])
      |> Enum.map(&normalize_host/1)
      |> MapSet.new()

    if MapSet.member?(allowed_hosts, normalize_host(conn.host)) do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(421, "Misdirected Request")
      |> halt()
    end
  end

  defp normalize_host(host) do
    host
    |> to_string()
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.downcase()
  end
end
