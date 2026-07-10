defmodule EirinchanWeb.Plugs.AccessLog do
  @moduledoc false

  import Plug.Conn
  require Logger

  alias Eirinchan.CredentialHash
  alias EirinchanWeb.RequestMeta

  def init(opts), do: opts

  def call(conn, _opts) do
    started_at = System.monotonic_time()

    client_id =
      conn
      |> RequestMeta.effective_remote_ip()
      |> RequestMeta.ip_to_string()
      |> CredentialHash.fingerprint(:access_log_ip)

    Logger.metadata(remote_ip: client_id)

    register_before_send(conn, fn conn ->
      Logger.info(render_line(conn, started_at, client_id))
      conn
    end)
  end

  defp render_line(conn, started_at, client_id) do
    request_id = Logger.metadata()[:request_id] || "-"

    [
      "access",
      "client_id=#{quote_field(client_id)}",
      "method=#{conn.method}",
      "path=#{quote_field(conn.request_path)}",
      "status=#{conn.status || 0}",
      "bytes=#{response_bytes(conn)}",
      "request_id=#{quote_field(to_string(request_id))}",
      "route=#{quote_field(route_name(conn))}",
      "duration_ms=#{duration_ms(started_at)}"
    ]
    |> Enum.join(" ")
  end

  defp response_bytes(conn) do
    case get_resp_header(conn, "content-length") |> List.first() do
      nil when is_binary(conn.resp_body) -> Integer.to_string(byte_size(conn.resp_body))
      nil -> "-"
      value -> value
    end
  end

  defp route_name(conn) do
    case {conn.private[:phoenix_controller], conn.private[:phoenix_action]} do
      {nil, nil} -> "-"
      {controller, action} -> "#{inspect(controller)}##{action}"
    end
  end

  defp duration_ms(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
    |> :erlang.float_to_binary(decimals: 1)
  end

  defp quote_field(value), do: ~s("#{escape_field(value)}")

  defp escape_field(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace(~r/[\r\n\t]/u, " ")
    |> String.slice(0, 512)
  end
end
