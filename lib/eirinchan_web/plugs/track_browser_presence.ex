defmodule EirinchanWeb.Plugs.TrackBrowserPresence do
  @moduledoc false

  alias Eirinchan.BrowserPresence

  def init(opts), do: opts

  def call(conn, _opts) do
    if trackable_request?(conn) do
      BrowserPresence.touch(conn.assigns[:browser_token])
    end

    conn
  end

  defp trackable_request?(%Plug.Conn{method: "GET", request_path: path}) do
    not String.starts_with?(path, "/manage") and
      path not in ["/auth", "/setup"]
  end

  defp trackable_request?(_conn), do: false
end
