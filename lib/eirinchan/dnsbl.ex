defmodule Eirinchan.DNSBL do
  @moduledoc false

  alias Eirinchan.IpMatching

  def check(ip, config, opts \\ [])
  def check(ip, _config, _opts) when ip in [nil, ""], do: :ok

  def check(ip, config, opts) do
    resolver = Keyword.get(opts, :resolver, &default_lookup/1)
    exceptions = List.wrap(Map.get(config, :dnsbl_exceptions, []))
    lists = List.wrap(Map.get(config, :dnsbl, []))

    cond do
      ipv6?(ip) -> :ok
      local_ip?(ip) -> :ok
      render_ip(ip) in exceptions -> :ok
      true -> check_lists(ip, lists, resolver)
    end
  end

  defp check_lists(_ip, [], _resolver), do: :ok

  defp check_lists(ip, [blacklist | rest], resolver) do
    case normalize_blacklist(blacklist) do
      {:ok, lookup_template, expectation, display_name} ->
        reversed_ip = reverse_ipv4_octets(ip)

        lookup =
          if String.contains?(lookup_template, "%") do
            String.replace(lookup_template, "%", reversed_ip)
          else
            "#{reversed_ip}.#{lookup_template}"
          end

        case resolver.(lookup) do
          nil ->
            check_lists(ip, rest, resolver)

          response ->
            if blocked_response?(response, expectation) do
              {:error, display_name}
            else
              check_lists(ip, rest, resolver)
            end
        end

      :error ->
        check_lists(ip, rest, resolver)
    end
  end

  defp blocked_response?(_response, nil), do: true

  defp blocked_response?(response, expected) when is_list(expected) do
    normalized = normalize_dns_response(response)
    Enum.any?(expected, fn octet -> normalized in [to_string(octet), "127.0.0.#{octet}"] end)
  end

  defp blocked_response?(response, %{type: "httpbl"} = expected) do
    httpbl_match?(normalize_dns_response(response), expected)
  end

  defp blocked_response?(response, expected) when is_map(expected) do
    expected
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
    |> case do
      %{"type" => "httpbl"} = map ->
        httpbl_match?(normalize_dns_response(response), %{
          type: "httpbl",
          max_days: map["max_days"],
          min_threat: map["min_threat"]
        })

      _ ->
        false
    end
  end

  defp blocked_response?(response, fun) when is_function(fun, 1),
    do: fun.(normalize_dns_response(response))

  defp blocked_response?(response, expected) do
    normalized = normalize_dns_response(response)
    normalized in [to_string(expected), "127.0.0.#{expected}"]
  end

  defp normalize_blacklist([lookup, expectation, name]),
    do: normalized_blacklist(lookup, expectation, name)

  defp normalize_blacklist([lookup, expectation]),
    do: normalized_blacklist(lookup, expectation, lookup)

  defp normalize_blacklist(%{} = blacklist) do
    lookup = Map.get(blacklist, "lookup") || Map.get(blacklist, :lookup)
    expectation = Map.get(blacklist, "expectation") || Map.get(blacklist, :expectation)
    name = Map.get(blacklist, "display_name") || Map.get(blacklist, :display_name) || lookup
    normalized_blacklist(lookup, expectation, name)
  end

  defp normalize_blacklist(lookup) when is_binary(lookup),
    do: normalized_blacklist(lookup, nil, lookup)

  defp normalize_blacklist(_blacklist), do: :error

  defp normalized_blacklist(lookup, expectation, name) when is_binary(lookup) do
    if String.trim(lookup) == "" or String.contains?(lookup, ["\r", "\n", <<0>>]) do
      :error
    else
      lookup = String.trim(lookup)
      display_name = if is_binary(name) and String.trim(name) != "", do: name, else: lookup
      {:ok, lookup, expectation, display_name}
    end
  end

  defp normalized_blacklist(_lookup, _expectation, _name), do: :error

  defp default_lookup(host) do
    case :inet_res.lookup(String.to_charlist(host), :in, :a) do
      [{a, b, c, d} | _] -> "#{a}.#{b}.#{c}.#{d}"
      _ -> nil
    end
  end

  defp reverse_ipv4_octets(ip) do
    ip
    |> render_ip()
    |> String.split(".")
    |> Enum.reverse()
    |> Enum.join(".")
  end

  defp normalize_dns_response({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp normalize_dns_response(value), do: to_string(value)

  defp render_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp render_ip(ip), do: to_string(ip)

  defp httpbl_match?(response, %{max_days: max_days, min_threat: min_threat})
       when is_integer(max_days) and is_integer(min_threat) do
    case String.split(response, ".") do
      ["127", days, threat, _type] ->
        with {parsed_days, ""} <- Integer.parse(days),
             {parsed_threat, ""} <- Integer.parse(threat) do
          parsed_days <= max_days and parsed_threat >= min_threat
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp httpbl_match?(_response, _expected), do: false

  defp ipv6?(ip) do
    case IpMatching.parse_ip(ip) do
      {:ok, {_a, _b, _c, _d, _e, _f, _g, _h}} -> true
      _ -> false
    end
  end

  defp local_ip?(ip) do
    ip_string = render_ip(ip)

    String.starts_with?(ip_string, "127.") or
      String.starts_with?(ip_string, "10.") or
      String.starts_with?(ip_string, "192.168.") or
      Regex.match?(~r/^172\.(1[6-9]|2[0-9]|3[0-1])\./, ip_string) or
      String.starts_with?(ip_string, "0.") or
      String.starts_with?(ip_string, "255.")
  end
end
