defmodule EirinchanWeb.Plugs.SecureHeaders do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.Settings

  @headers [
    {"x-frame-options", "SAMEORIGIN"},
    {"x-content-type-options", "nosniff"},
    {"referrer-policy", "strict-origin-when-cross-origin"},
    {"x-permitted-cross-domain-policies", "none"}
  ]

  @permissions_policy [
    "accelerometer=()",
    "autoplay=(self)",
    "camera=()",
    "display-capture=()",
    "fullscreen=(self)",
    "geolocation=()",
    "gyroscope=()",
    "magnetometer=()",
    "microphone=()",
    "payment=()",
    "usb=()"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    config = Settings.current_instance_config()

    if Map.get(config, :security_headers, true) do
      conn
      |> put_standard_headers()
      |> put_resp_header("permissions-policy", Enum.join(@permissions_policy, ", "))
    else
      conn
    end
  end

  defp put_standard_headers(conn) do
    Enum.reduce(@headers, conn, fn {key, value}, acc ->
      put_resp_header(acc, key, value)
    end)
  end

end
