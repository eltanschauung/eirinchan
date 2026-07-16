defmodule EirinchanWeb.Plugs.SecureHeaders do
  @moduledoc false

  import Plug.Conn

  @headers [
    {"x-frame-options", "SAMEORIGIN"},
    {"x-content-type-options", "nosniff"},
    {"referrer-policy", "strict-origin-when-cross-origin"},
    {"x-permitted-cross-domain-policies", "none"}
  ]

  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "base-uri 'none'",
                               "object-src 'none'",
                               "frame-ancestors 'self'",
                               "form-action 'self'",
                               "script-src 'self' blob: 'wasm-unsafe-eval'",
                               "style-src 'self' 'unsafe-inline'",
                               "img-src 'self' data: blob: https:",
                               "media-src 'self' blob: https:",
                               "font-src 'self' data:",
                               "connect-src 'self' https: wss:",
                               "frame-src https:",
                               "worker-src 'self' blob:",
                               "manifest-src 'self'"
                             ],
                             "; "
                           )

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
    conn
    |> put_standard_headers()
    |> put_resp_header("content-security-policy", @content_security_policy)
    |> put_resp_header("permissions-policy", Enum.join(@permissions_policy, ", "))
  end

  defp put_standard_headers(conn) do
    Enum.reduce(@headers, conn, fn {key, value}, acc ->
      put_resp_header(acc, key, value)
    end)
  end
end
