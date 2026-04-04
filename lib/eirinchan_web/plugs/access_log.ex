defmodule EirinchanWeb.Plugs.AccessLog do
  @moduledoc false

  import Plug.Conn
  require Logger

  alias EirinchanWeb.RequestMeta

  def init(opts), do: opts

  def call(conn, _opts) do
    started_at = System.monotonic_time()
    client_ip = RequestMeta.effective_remote_ip(conn) |> RequestMeta.ip_to_string()

    Logger.metadata(remote_ip: client_ip)

    register_before_send(conn, fn conn ->
      Logger.info(render_line(conn, started_at, client_ip))
      conn
    end)
  end

  defp render_line(conn, started_at, client_ip) do
    peer_ip = RequestMeta.ip_to_string(conn.remote_ip)
    forwarded_for = header(conn, "x-forwarded-for")
    referer = header(conn, "referer")
    user_agent = header(conn, "user-agent")
    request_id = Logger.metadata()[:request_id] || "-"
    target = RequestMeta.request_target(conn)
    status = conn.status || 0
    bytes = response_bytes(conn)
    host = RequestMeta.request_host(conn)
    route = route_name(conn)
    duration_ms = duration_ms(started_at)

    [
      "access",
      client_ip,
      "peer=#{quote_field(peer_ip)}",
      "forwarded_for=#{quote_field(forwarded_for)}",
      "- -",
      "[#{timestamp()}]",
      ~s("#{conn.method} #{escape_field(target)} #{String.upcase(to_string(conn.scheme))}"),
      Integer.to_string(status),
      bytes,
      quote_field(referer),
      quote_field(user_agent),
      "host=#{quote_field(host)}",
      "request_id=#{quote_field(to_string(request_id))}",
      "route=#{quote_field(route)}",
      "duration_ms=#{duration_ms}"
    ]
    |> Enum.join(" ")
  end

  defp response_bytes(conn) do
    case get_resp_header(conn, "content-length") |> List.first() do
      nil ->
        if is_binary(conn.resp_body) do
          byte_size(conn.resp_body) |> Integer.to_string()
        else
          "-"
        end

      value ->
        value
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

  defp header(conn, name) do
    conn
    |> get_req_header(name)
    |> List.first()
    |> default_dash()
  end

  defp default_dash(nil), do: "-"
  defp default_dash(""), do: "-"
  defp default_dash(value), do: value

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%d/%b/%Y:%H:%M:%S +0000")
  end

  defp quote_field(value), do: ~s("#{escape_field(value)}")

  defp escape_field(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace(~r/[\r\n\t]/u, " ")
  end
end
