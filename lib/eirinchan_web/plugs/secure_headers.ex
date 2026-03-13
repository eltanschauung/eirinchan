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
      |> put_resp_header("content-security-policy", content_security_policy(config))
    else
      conn
    end
  end

  defp put_standard_headers(conn) do
    Enum.reduce(@headers, conn, fn {key, value}, acc ->
      put_resp_header(acc, key, value)
    end)
  end

  defp content_security_policy(config) do
    script_src =
      ["'self'"] ++
        if(Map.get(config, :allow_remote_script_urls, false), do: ["https:", "http:"], else: [])

    [
      {"default-src", ["'self'"]},
      {"base-uri", ["'self'"]},
      {"object-src", ["'none'"]},
      {"frame-ancestors", ["'self'"]},
      {"form-action", ["'self'"]},
      {"script-src", script_src},
      {"style-src", ["'self'", "'unsafe-inline'"]},
      {"img-src", ["'self'", "data:", "blob:", "https:"]},
      {"media-src", ["'self'", "blob:", "data:"]},
      {"font-src", ["'self'", "data:"]},
      {"connect-src", ["'self'", "ws:", "wss:"]},
      {"frame-src", ["'self'", "https://www.youtube.com", "https://www.youtube-nocookie.com"]},
      {"worker-src", ["'self'", "blob:"]}
    ]
    |> Enum.map(fn {directive, sources} -> "#{directive} #{Enum.join(sources, " ")}" end)
    |> Enum.join("; ")
  end
end
