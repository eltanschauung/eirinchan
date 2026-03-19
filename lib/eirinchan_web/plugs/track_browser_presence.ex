defmodule EirinchanWeb.Plugs.TrackBrowserPresence do
  @moduledoc false

  alias Eirinchan.BrowserPresence
  alias EirinchanWeb.CrawlerDetector

  def init(opts), do: opts

  def call(conn, _opts) do
    if trackable_request?(conn) do
      BrowserPresence.touch(conn.assigns[:browser_token])
    end

    conn
  end

  defp trackable_request?(%Plug.Conn{} = conn) do
    request_trackable_path?(conn) and not crawler_request?(conn)
  end

  defp trackable_request?(_conn), do: false

  defp request_trackable_path?(%Plug.Conn{method: "GET", request_path: path}) do
    not String.starts_with?(path, "/manage") and path not in ["/auth", "/setup"]
  end

  defp request_trackable_path?(_conn), do: false

  defp crawler_request?(conn) do
    conn
    |> Plug.Conn.get_req_header("user-agent")
    |> List.first()
    |> CrawlerDetector.crawler?()
  end
end
