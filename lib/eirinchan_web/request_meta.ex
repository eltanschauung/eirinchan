defmodule EirinchanWeb.RequestMeta do
  @moduledoc false

  alias Eirinchan.IpMatching
  alias Eirinchan.BrowserIdentity
  import Plug.Conn

  @default_config %{
    trust_headers: false,
    trusted_ips: [],
    trusted_cidrs: [],
    client_ip_headers: ["x-forwarded-for", "x-real-ip"]
  }

  def effective_remote_ip(conn) do
    config = config()
    remote_ip = conn.remote_ip

    if config.trust_headers and trusted_proxy?(remote_ip, config) do
      forwarded_client_ip(conn, config) || remote_ip
    else
      remote_ip
    end
  end

  def public_identity(conn) do
    %{
      remote_ip: effective_remote_ip(conn),
      browser_ref: browser_ref(conn)
    }
  end

  def browser_ref(conn) do
    case conn.assigns[:browser_token] do
      reference when is_binary(reference) ->
        if BrowserIdentity.reference?(reference), do: reference

      _ ->
        nil
    end
  end

  def forwarded_for(conn) do
    config = config()

    if config.trust_headers and trusted_proxy?(conn.remote_ip, config) do
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()
    end
  end

  def request_host(conn) do
    port = conn.port

    if default_port?(conn.scheme, port) do
      conn.host
    else
      "#{conn.host}:#{port}"
    end
  end

  def request_target(conn) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    conn.request_path <> query
  end

  def ip_to_string({_, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()
  def ip_to_string({_, _, _, _, _, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()
  def ip_to_string(value) when is_binary(value), do: String.trim(value)
  def ip_to_string(nil), do: "-"
  def ip_to_string(value), do: inspect(value)

  def trusted_proxy?(remote_ip, config \\ config()) do
    IpMatching.match?(remote_ip, config.trusted_ips) or
      IpMatching.match?(remote_ip, config.trusted_cidrs)
  end

  defp forwarded_client_ip(conn, config) do
    Enum.reduce_while(config.client_ip_headers, nil, fn header, _client_ip ->
      case get_req_header(conn, header) do
        [] ->
          {:cont, nil}

        [value] ->
          {:halt, extract_client_ip(value, header, conn.remote_ip, config)}

        _duplicates ->
          {:halt, nil}
      end
    end)
  end

  defp extract_client_ip(value, "x-forwarded-for", remote_ip, config) do
    with {:ok, forwarded_ips} <- parse_forwarded_chain(value) do
      forwarded_ips
      |> Kernel.++([remote_ip])
      |> Enum.reverse()
      |> Enum.find(&(not trusted_proxy?(&1, config)))
    else
      :error -> nil
    end
  end

  defp extract_client_ip(value, _header, _remote_ip, _config),
    do: parsed_ip(String.trim(value))

  defp parse_forwarded_chain(value) when is_binary(value) do
    value
    |> String.split(",", trim: false)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, ips} ->
      case parse_ip(String.trim(part)) do
        {:ok, ip} -> {:cont, {:ok, [ip | ips]}}
        _error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, []} -> :error
      {:ok, ips} -> {:ok, Enum.reverse(ips)}
      :error -> :error
    end
  end

  defp parse_forwarded_chain(_value), do: :error

  defp parse_ip(value) when is_binary(value) do
    IpMatching.parse_ip(value)
  end

  defp parse_ip(value) when is_tuple(value), do: {:ok, value}
  defp parse_ip(_value), do: :error

  defp parsed_ip(value) do
    case parse_ip(value) do
      {:ok, ip} -> ip
      _ -> nil
    end
  end

  defp default_port?(:http, 80), do: true
  defp default_port?(:https, 443), do: true
  defp default_port?("http", 80), do: true
  defp default_port?("https", 443), do: true
  defp default_port?(_, _), do: false

  defp config do
    @default_config
    |> Map.merge(Application.get_env(:eirinchan, :proxy_request, %{}))
    |> Map.update!(:trusted_ips, &List.wrap/1)
    |> Map.update!(:trusted_cidrs, &List.wrap/1)
    |> Map.update!(
      :client_ip_headers,
      &Enum.map(List.wrap(&1), fn value -> String.downcase(to_string(value)) end)
    )
  end
end
