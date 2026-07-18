defmodule EirinchanWeb.Plugs.GoAwayApi do
  @moduledoc false

  import Plug.Conn

  alias Eirinchan.AccessList
  alias Eirinchan.Statistics.Report
  alias Eirinchan.Settings
  alias EirinchanWeb.Plugs.PrivateLoopback
  alias EirinchanWeb.RequestMeta

  @statistics_paths ["/__goaway/api/statistics", "/__goaway/statistics"]
  @ip_access_path "/__goaway/api/ipaccess"
  @default_hours 1
  @max_hours 168

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET"} = conn, opts) do
    cond do
      not PrivateLoopback.request?(conn) -> conn
      conn.request_path in @statistics_paths -> serve_statistics(conn, opts)
      conn.request_path == @ip_access_path -> serve_ip_access(conn, opts)
      true -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp serve_statistics(conn, opts) do
    conn = fetch_query_params(conn)

    config = Settings.effective_instance_config()

    case timeframe_hours(conn.query_params["hours"], config) do
      {:ok, hours} ->
        fetcher = Keyword.get(opts, :report_fetcher, &Report.build/1)
        send_json(conn, 200, fetch_report(fetcher, hours, config))

      {:error, message} ->
        send_json(conn, 400, %{error: message})
    end
  rescue
    _error -> send_json(conn, 503, %{error: "statistics_unavailable"})
  end

  defp serve_ip_access(conn, opts) do
    allowed? = Keyword.get(opts, :allowed?, &AccessList.allowed_for_posting?/1)
    remote_ip = RequestMeta.effective_remote_ip(conn)
    status = if allowed?.(remote_ip), do: 204, else: 403
    send_empty(conn, status)
  rescue
    _error -> send_empty(conn, 503)
  end

  defp timeframe_hours(nil, config), do: {:ok, default_hours(config)}
  defp timeframe_hours("", config), do: {:ok, default_hours(config)}

  defp timeframe_hours(value, config) when is_binary(value) do
    maximum = max_hours(config)

    case Integer.parse(value) do
      {hours, ""} when hours >= 1 and hours <= maximum -> {:ok, hours}
      _other -> {:error, "hours must be an integer from 1 through #{maximum}"}
    end
  end

  defp fetch_report(fetcher, hours, config) when is_function(fetcher, 2),
    do: fetcher.(hours, config: config)

  defp fetch_report(fetcher, hours, _config), do: fetcher.(hours)

  defp default_hours(config) do
    configured = positive_integer(config, :statistics_api_default_hours, @default_hours)
    min(configured, max_hours(config))
  end

  defp max_hours(config) do
    config
    |> positive_integer(:statistics_api_max_hours, @max_hours)
    |> min(8_760)
  end

  defp positive_integer(config, key, default) do
    case Map.get(config, key, default) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
    |> halt()
  end

  defp send_empty(conn, status) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, "")
    |> halt()
  end
end
