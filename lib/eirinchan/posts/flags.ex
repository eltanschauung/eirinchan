defmodule Eirinchan.Posts.Flags do
  @moduledoc false

  alias Eirinchan.GeoIp

  @spec normalize(map(), map(), map()) :: {:ok, map()} | {:error, :invalid_user_flag}
  def normalize(attrs, config, request) do
    with {:ok, attrs} <- normalize_country_flag(attrs, config, request),
         {:ok, attrs} <- normalize_user_flag(attrs, config, request) do
      {:ok, attrs}
    end
  end

  defp normalize_country_flag(attrs, %{country_flags: false}, _request) do
    {:ok, attrs |> Map.put_new("flag_codes", []) |> Map.put_new("flag_alts", [])}
  end

  defp normalize_country_flag(attrs, config, request) do
    if config.allow_no_country and truthy?(Map.get(attrs, "no_country")) do
      {:ok, attrs |> Map.put("flag_codes", []) |> Map.put("flag_alts", [])}
    else
      case resolve_country_flag(config, request, false) do
        nil ->
          {:ok, attrs |> Map.put("flag_codes", []) |> Map.put("flag_alts", [])}

        {code, alt} ->
          {:ok, attrs |> Map.put("flag_codes", [code]) |> Map.put("flag_alts", [alt])}
      end
    end
  end

  defp normalize_user_flag(attrs, %{user_flag: false}, _request) do
    {:ok, attrs |> Map.put_new("flag_codes", []) |> Map.put_new("flag_alts", [])}
  end

  defp normalize_user_flag(attrs, config, request) do
    allowed_flags =
      config.user_flags
      |> Enum.into(%{}, fn {flag, text} ->
        {flag |> to_string() |> String.trim() |> String.downcase(), to_string(text)}
      end)

    default_flag_source = trim_to_nil(config.default_user_flag) || "country"
    country_fallback_code = config.country_flag_fallback.code |> to_string() |> String.downcase()

    default_flags =
      with {:ok, parsed_flags} <- parse_user_flags(default_flag_source, config.multiple_flags),
           {:ok, validated_flags} <- validate_user_flags(parsed_flags, allowed_flags, country_fallback_code) do
        validated_flags
      end

    fallback_flags = [country_fallback_code]

    selected_flags =
      case Map.get(attrs, "user_flag", :missing) do
        :missing ->
          default_flags

        raw_flags when is_binary(raw_flags) ->
          case trim_to_nil(raw_flags) do
            nil ->
              fallback_flags

            trimmed_flags ->
              with {:ok, parsed_flags} <- parse_user_flags(trimmed_flags, config.multiple_flags),
                   {:ok, validated_flags} <-
                     validate_user_flags(parsed_flags, allowed_flags, country_fallback_code) do
                validated_flags
              end
          end

        _ ->
          default_flags
      end

    case selected_flags do
      {:error, :invalid_user_flag} ->
        {:error, :invalid_user_flag}

      [] ->
        {:ok, attrs |> Map.put_new("flag_codes", []) |> Map.put_new("flag_alts", [])}

      flags when is_list(flags) ->
        existing_pairs =
          Enum.zip(Map.get(attrs, "flag_codes", []), Map.get(attrs, "flag_alts", []))

        resolved_pairs =
          Enum.map(flags, fn flag ->
            resolve_user_flag(flag, allowed_flags, config, request)
          end)

        pairs = existing_pairs ++ resolved_pairs

        {:ok,
         attrs
         |> Map.put("flag_codes", Enum.map(pairs, &elem(&1, 0)))
         |> Map.put("flag_alts", Enum.map(pairs, &elem(&1, 1)))}
    end
  end

  defp resolve_user_flag("country", _allowed_flags, config, request) do
    resolve_country_flag(config, request, true)
  end

  defp resolve_user_flag(flag, allowed_flags, config, _request) do
    fallback_code = config.country_flag_fallback.code |> to_string() |> String.downcase()

    if flag == fallback_code do
      normalize_country_metadata(config.country_flag_fallback)
    else
      {flag, Map.fetch!(allowed_flags, flag)}
    end
  end

  defp parse_user_flags(nil, _multiple_flags), do: {:ok, []}

  defp parse_user_flags(raw_flags, true) do
    if String.length(raw_flags) > 300 do
      {:error, :invalid_user_flag}
    else
      {:ok,
       raw_flags
       |> String.split(",", trim: false)
       |> normalize_user_flag_tokens()}
    end
  end

  defp parse_user_flags(raw_flags, false) do
    {:ok, normalize_user_flag_tokens([raw_flags])}
  end

  defp validate_user_flags(flags, allowed_flags, country_fallback_code) when is_list(flags) do
    if Enum.all?(flags, fn flag ->
         flag == "country" or flag == country_fallback_code or Map.has_key?(allowed_flags, flag)
       end) do
      {:ok, flags}
    else
      {:error, :invalid_user_flag}
    end
  end

  defp normalize_user_flag_tokens(tokens) do
    tokens
    |> Enum.map(&(String.trim(&1) |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
  end

  defp resolve_country_flag(config, request, allow_fallback?) do
    case country_metadata(request, config) do
      {code, alt} ->
        {code, alt}

      nil when allow_fallback? ->
        normalize_country_metadata(config.country_flag_fallback)

      nil ->
        nil
    end
  end

  defp request_country_metadata(request) do
    Map.get(request, :country) || Map.get(request, "country") ||
      case {Map.get(request, :country_code) || Map.get(request, "country_code"),
            Map.get(request, :country_name) || Map.get(request, "country_name")} do
        {nil, nil} -> nil
        {code, name} -> %{code: code, name: name}
      end
  end

  defp request_remote_ip(request) do
    case Map.get(request, :remote_ip) || Map.get(request, "remote_ip") do
      nil -> nil
      ip -> normalize_ip(ip)
    end
  end

  defp lookup_country_metadata(nil, _country_flag_data), do: nil

  defp lookup_country_metadata(remote_ip, country_flag_data) when is_map(country_flag_data) do
    Map.get(country_flag_data, remote_ip) || Map.get(country_flag_data, to_string(remote_ip)) ||
      remote_ip
  end

  defp lookup_country_metadata(remote_ip, _country_flag_data), do: remote_ip

  defp country_metadata(request, config) do
    request
    |> request_country_metadata()
    |> case do
      nil ->
        request
        |> request_remote_ip()
        |> lookup_country_metadata(config.country_flag_data)
        |> case do
          %{code: _code, name: _name} = metadata ->
            metadata

          remote_ip ->
            case GeoIp.lookup_country(remote_ip, config) do
              {:ok, metadata} -> metadata
              :error -> nil
            end
        end

      metadata ->
        metadata
    end
    |> normalize_country_metadata()
    |> reject_excluded_country(config.country_flag_exclusions)
  end

  defp normalize_country_metadata(nil), do: nil
  defp normalize_country_metadata(%{code: code, name: name}), do: normalize_country_metadata({code, name})
  defp normalize_country_metadata(%{"code" => code, "name" => name}), do: normalize_country_metadata({code, name})
  defp normalize_country_metadata([code, name]), do: normalize_country_metadata({code, name})

  defp normalize_country_metadata({code, name}) do
    normalized_code = code |> to_string() |> String.trim() |> String.downcase()
    normalized_name = name |> to_string() |> String.trim()

    if normalized_code == "" or normalized_name == "" do
      nil
    else
      {normalized_code, normalized_name}
    end
  end

  defp reject_excluded_country(nil, _excluded_codes), do: nil
  defp reject_excluded_country({code, alt}, excluded_codes), do: if(code in excluded_codes, do: nil, else: {code, alt})

  defp normalize_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp normalize_ip({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp normalize_ip(ip) when is_binary(ip), do: String.trim(ip)

  defp trim_to_nil(nil), do: nil

  defp trim_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp truthy?(value) when value in [true, "true", "1", 1, "on"], do: true
  defp truthy?(_value), do: false
end
