defmodule Eirinchan.Tf2PlayerCount do
  @moduledoc false

  @default_url "https://kogasa.tf/api/playercount"
  @default_timeout_ms 2_000
  @default_cache_seconds 60
  @maximum_response_bytes 64 * 1_024

  alias Eirinchan.Settings

  @type stats :: %{
          display: String.t(),
          player_count: non_neg_integer(),
          available?: boolean()
        }

  @spec fetch(keyword()) :: {:ok, stats()} | {:error, term()}
  def fetch(opts \\ []) do
    result =
      case Keyword.get(opts, :fetcher) do
        fetcher when is_function(fetcher, 0) -> fetcher.()
        _ ->
          request(
            config(:tf2_player_count_url, :url, @default_url),
            config(:tf2_player_count_timeout_ms, :timeout_ms, @default_timeout_ms)
            |> bounded_positive(@default_timeout_ms, 60_000)
          )
      end

    normalize_result(result)
  rescue
    _ -> {:error, :request_failed}
  catch
    _, _ -> {:error, :request_failed}
  end

  @spec parse_response(binary()) :: {:ok, stats()} | {:error, term()}
  def parse_response(body) when is_binary(body) and byte_size(body) <= @maximum_response_bytes do
    with {:ok, payload} <- Jason.decode(body) do
      normalize_payload(payload)
    else
      _ -> {:error, :invalid_response}
    end
  end

  def parse_response(_body), do: {:error, :invalid_response}

  @spec unavailable() :: stats()
  def unavailable, do: %{display: "unavailable", player_count: 0, available?: false}

  @spec cache_seconds() :: pos_integer()
  def cache_seconds do
    case config(
           :tf2_player_count_cache_seconds,
           :cache_seconds,
           @default_cache_seconds
         ) do
      value when is_integer(value) and value > 0 -> min(value, 3_600)
      _ -> @default_cache_seconds
    end
  end

  defp request(url, timeout) when is_binary(url) and is_integer(timeout) and timeout > 0 do
    with %URI{scheme: "https", host: host} when is_binary(host) <- URI.parse(url) do
      ssl_options = [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(host),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]

      case :httpc.request(
             :get,
             {String.to_charlist(url), [{~c"accept", ~c"application/json"}]},
             [
               timeout: timeout,
               connect_timeout: timeout,
               autoredirect: false,
               ssl: ssl_options
             ],
             body_format: :binary
           ) do
        {:ok, {{_version, 200, _reason}, _headers, body}} -> {:ok, body}
        {:ok, {{_version, status, _reason}, _headers, _body}} -> {:error, {:http_status, status}}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :invalid_url}
    end
  end

  defp request(_url, _timeout), do: {:error, :invalid_config}

  defp normalize_result({:ok, body}) when is_binary(body), do: parse_response(body)
  defp normalize_result({:ok, payload}) when is_map(payload), do: normalize_payload(payload)
  defp normalize_result({:error, _reason} = error), do: error
  defp normalize_result(_result), do: {:error, :invalid_response}

  defp normalize_payload(%{
         "success" => true,
         "display" => display,
         "player_count" => player_count
       })
       when is_binary(display) and is_integer(player_count) and player_count >= 0 do
    if valid_display?(display) do
      {:ok, %{display: display, player_count: player_count, available?: true}}
    else
      {:error, :invalid_response}
    end
  end

  defp normalize_payload(_payload), do: {:error, :invalid_response}

  defp valid_display?(display) do
    byte_size(display) in 1..64 and
      String.valid?(display) and
      not Regex.match?(~r/[\x00-\x1F\x7F]/u, display)
  end

  defp config(instance_key, legacy_key, default) do
    instance = Settings.current_instance_config()

    if Map.has_key?(instance, instance_key) do
      Map.get(instance, instance_key)
    else
      case Application.get_env(:eirinchan, :tf2_player_count, []) do
        settings when is_list(settings) -> Keyword.get(settings, legacy_key, default)
        settings when is_map(settings) -> Map.get(settings, legacy_key, default)
        _ -> default
      end
    end
  end

  defp bounded_positive(value, _default, maximum) when is_integer(value) and value > 0,
    do: min(value, maximum)

  defp bounded_positive(_value, default, _maximum), do: default
end
