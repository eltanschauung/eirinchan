defmodule EirinchanWeb.Plugs.TrackBrowserPresence do
  @moduledoc false

  alias Eirinchan.BrowserPresence
  alias Eirinchan.VisitorQualification
  alias EirinchanWeb.CrawlerDetector
  alias EirinchanWeb.RequestMeta

  def init(opts), do: opts

  def call(conn, opts) do
    if request_trackable_path?(conn) do
      track_browser(conn, opts)
    end

    conn
  end

  defp track_browser(conn, opts) do
    browser_ref = conn.assigns[:browser_ref]
    issued_at = conn.assigns[:browser_identity_issued_at]

    cond do
      conn.assigns[:returning_browser_identity] != true ->
        VisitorQualification.record_issue(browser_ref, client_bucket(conn), issued_at, opts)

      crawler_request?(conn) ->
        VisitorQualification.exclude_crawler(browser_ref, opts)

      VisitorQualification.qualify(browser_ref, issued_at, opts) == :qualified ->
        BrowserPresence.touch(browser_ref)

      true ->
        :ok
    end
  end

  defp client_bucket(conn) do
    address =
      conn
      |> RequestMeta.effective_remote_ip()
      |> RequestMeta.ip_to_string()

    browser_features = [
      request_header(conn, "user-agent"),
      request_header(conn, "accept-language"),
      request_header(conn, "sec-ch-ua"),
      request_header(conn, "sec-ch-ua-platform"),
      request_header(conn, "sec-ch-ua-mobile")
    ]

    VisitorQualification.client_bucket(address, browser_features)
  end

  defp request_trackable_path?(%Plug.Conn{method: "GET", request_path: path}) do
    not String.starts_with?(path, "/manage") and path != "/auth"
  end

  defp request_trackable_path?(_conn), do: false

  defp crawler_request?(conn) do
    conn
    |> Plug.Conn.get_req_header("user-agent")
    |> List.first()
    |> CrawlerDetector.crawler?()
  end

  defp request_header(conn, name) do
    conn
    |> Plug.Conn.get_req_header(name)
    |> List.first()
    |> to_string()
  end
end
