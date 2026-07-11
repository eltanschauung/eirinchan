defmodule Eirinchan.Purge do
  @moduledoc false

  def purge_uri(uri, config, opts \\ []) do
    timeout = purge_timeout(config, opts)

    if valid_request_value?(uri) and String.starts_with?(uri, "/") do
      Enum.each(List.wrap(Map.get(config, :purge, [])), fn target ->
        {host, port, http_host} = normalize_target(target)

        if valid_target?(host, port, http_host) do
          request =
            "PURGE #{uri} HTTP/1.1\r\nHost: #{http_host}\r\nUser-Agent: Eirinchan\r\nConnection: Close\r\n\r\n"

          with {:ok, socket} <-
                 :gen_tcp.connect(
                   String.to_charlist(host),
                   port,
                   [:binary, active: false],
                   timeout
                 ),
               :ok <- :gen_tcp.send(socket, request) do
            :gen_tcp.close(socket)
          else
            _ -> :ok
          end
        end
      end)
    end

    :ok
  end

  def purge_output_path(path, config, opts \\ []) do
    uri = output_uri(path, opts)

    if uri do
      purge_uri(uri, config, opts)

      if String.ends_with?(uri, "/index.html") do
        purge_uri(String.replace_suffix(uri, "index.html", ""), config, opts)
      end
    end

    :ok
  end

  def output_uri(path, opts \\ []) do
    root = Keyword.get(opts, :board_root, Application.get_env(:eirinchan, :build_output_root))

    if is_binary(path) and is_binary(root) do
      relative = Path.relative_to(Path.expand(path), Path.expand(root))

      if relative == "." or not outside_root?(relative) do
        normalized = if relative == ".", do: "", else: String.replace(relative, "\\", "/")
        "/" <> normalized
      end
    end
  end

  defp purge_timeout(config, opts) do
    configured = Map.get(config, :purge_timeout_seconds, 3)
    default = if is_integer(configured) and configured > 0, do: configured * 1_000, else: 3_000

    case Keyword.get(opts, :timeout, default) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _ -> default
    end
  end

  defp outside_root?(relative) do
    Path.type(relative) == :absolute or relative == ".." or String.starts_with?(relative, "../") or
      String.starts_with?(relative, "..\\")
  end

  defp valid_target?(host, port, http_host) do
    valid_request_value?(host) and valid_request_value?(http_host) and
      is_integer(port) and port in 1..65_535
  end

  defp valid_request_value?(value) when is_binary(value) do
    value != "" and not String.contains?(value, ["\r", "\n", <<0>>])
  end

  defp valid_request_value?(_value), do: false

  defp normalize_target(%{host: host, port: port} = target) do
    {host, port, Map.get(target, :http_host, Map.get(target, "http_host", host))}
  end

  defp normalize_target(%{"host" => host, "port" => port} = target) do
    {host, port, Map.get(target, "http_host", host)}
  end

  defp normalize_target([host, port, http_host]), do: {host, port, http_host}
  defp normalize_target([host, port]), do: {host, port, host}
  defp normalize_target(_target), do: {nil, nil, nil}
end
