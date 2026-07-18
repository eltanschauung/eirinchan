defmodule EirinchanWeb.Plugs.GoAwayStatistics do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.Statistics.Report
  alias EirinchanWeb.Plugs.PrivateLoopback

  @path "/__goaway/statistics"
  @default_hours 1
  @max_hours 168

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: @path} = conn, opts) do
    if PrivateLoopback.request?(conn) do
      conn = fetch_query_params(conn)

      case timeframe_hours(conn.query_params["hours"]) do
        {:ok, hours} ->
          fetcher = Keyword.get(opts, :report_fetcher, &Report.build/1)
          send_json(conn, 200, fetcher.(hours))

        {:error, message} ->
          send_json(conn, 400, %{error: message})
      end
    else
      conn
    end
  rescue
    _error -> send_json(conn, 503, %{error: "statistics_unavailable"})
  end

  def call(conn, _opts), do: conn

  defp timeframe_hours(nil), do: {:ok, @default_hours}
  defp timeframe_hours(""), do: {:ok, @default_hours}

  defp timeframe_hours(value) when is_binary(value) do
    case Integer.parse(value) do
      {hours, ""} when hours in 1..@max_hours -> {:ok, hours}
      _other -> {:error, "hours must be an integer from 1 through #{@max_hours}"}
    end
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
    |> halt()
  end
end
