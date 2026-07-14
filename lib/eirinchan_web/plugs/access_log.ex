defmodule EirinchanWeb.Plugs.AccessLog do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.AccessLog
  alias Eirinchan.CredentialHash
  alias EirinchanWeb.RequestMeta

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  def init(opts), do: opts

  def call(conn, _opts) do
    client_id =
      conn
      |> RequestMeta.effective_remote_ip()
      |> RequestMeta.ip_to_string()
      |> CredentialHash.fingerprint(:access_log_ip)

    Logger.metadata(remote_ip: client_id)

    register_before_send(conn, fn conn ->
      unless skip_access_log?(conn) do
        _ = AccessLog.write(format_line(conn, goaccess_host(client_id)))
      end

      conn
    end)
  end

  defp skip_access_log?(%Plug.Conn{
         method: "POST",
         request_path: "/api/you-markers/bant",
         status: status
       })
       when status in 200..299,
       do: true

  defp skip_access_log?(_conn), do: false

  @doc false
  def goaccess_host(client_id) when is_binary(client_id) do
    # GoAccess requires %h to be an IP address. Embed the 96-bit HMAC
    # fingerprint in the documentation-only IPv6 prefix so the value remains
    # useful for aggregate traffic analysis without recording a client IP.
    with {:ok, <<a::16, b::16, c::16, d::16, e::16, f::16>>} <-
           Base.url_decode64(client_id, padding: false) do
      [0x2001, 0xDB8, a, b, c, d, e, f]
      |> Enum.map_join(":", &Integer.to_string(&1, 16))
      |> String.downcase()
    else
      _ -> "2001:db8::"
    end
  end

  @doc false
  def format_line(conn, client_id, now \\ DateTime.utc_now()) do
    [
      escape_field(client_id, 128),
      " - - [",
      timestamp(now),
      "] \"",
      escape_field(request_line(conn), 2_048),
      "\" ",
      Integer.to_string(conn.status || 0),
      " ",
      response_bytes(conn),
      " \"",
      escape_field(safe_referer(conn), 512),
      "\" \"",
      escape_field(header(conn, "user-agent"), 512),
      "\"\n"
    ]
    |> IO.iodata_to_binary()
  rescue
    _ -> "- - - [#{timestamp(now)}] \"-\" 0 - \"-\" \"-\"\n"
  end

  defp response_bytes(conn) do
    case get_resp_header(conn, "content-length") |> List.first() do
      nil when not is_nil(conn.resp_body) -> body_size(conn.resp_body)
      nil -> "-"
      value -> value
    end
  end

  defp body_size(body) do
    body |> IO.iodata_length() |> Integer.to_string()
  rescue
    _ -> "-"
  end

  defp request_line(conn), do: "#{conn.method} #{conn.request_path} HTTP/1.1"

  defp safe_referer(conn) do
    case header(conn, "referer") do
      "-" ->
        "-"

      value ->
        case URI.parse(value) do
          %URI{scheme: scheme, host: host} = uri
          when scheme in ["http", "https"] and is_binary(host) ->
            %{uri | query: nil, fragment: nil, userinfo: nil} |> URI.to_string()

          _ ->
            "-"
        end
    end
  rescue
    _ -> "-"
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] when value != "" -> value
      _ -> "-"
    end
  end

  defp timestamp(now) do
    month = Enum.at(@months, now.month - 1)

    :io_lib.format(
      "~2..0B/~s/~4..0B:~2..0B:~2..0B:~2..0B +0000",
      [now.day, month, now.year, now.hour, now.minute, now.second]
    )
    |> IO.iodata_to_binary()
  end

  defp escape_field(value, limit) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace(~r/[\r\n\t]/u, " ")
    |> String.slice(0, limit)
  end
end
