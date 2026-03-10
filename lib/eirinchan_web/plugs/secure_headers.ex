defmodule EirinchanWeb.Plugs.SecureHeaders do
  @moduledoc false

  import Plug.Conn

  @headers [
    {"x-frame-options", "SAMEORIGIN"},
    {"x-content-type-options", "nosniff"},
    {"referrer-policy", "strict-origin-when-cross-origin"},
    {"permissions-policy", "camera=(), microphone=(), geolocation=()"}
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    Enum.reduce(@headers, conn, fn {key, value}, acc ->
      put_resp_header(acc, key, value)
    end)
  end
end
