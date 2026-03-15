defmodule Eirinchan.Posts.Metadata do
  @moduledoc false

  alias Eirinchan.Tripcode

  @spec normalize(map(), map(), map(), boolean()) :: {:ok, map()}
  def normalize(attrs, config, request, op?) do
    attrs =
      attrs
      |> normalize_post_identity(config)
      |> put_request_ip(request)

    with {:ok, attrs} <- normalize_post_tag(attrs, config, op?),
         {:ok, attrs} <- normalize_proxy(attrs, config, request),
         {:ok, attrs} <- normalize_moderator_metadata(attrs, request) do
      {:ok, attrs}
    end
  end

  defp normalize_post_identity(attrs, config) do
    attrs
    |> Map.update("name", config.anonymous, &default_name(&1, config))
    |> normalize_tripcode(config)
    |> Map.update("subject", nil, &trim_to_nil/1)
    |> Map.update("password", nil, &trim_to_nil/1)
    |> Map.update("email", nil, &normalize_email/1)
  end

  defp default_name(nil, config), do: config.anonymous

  defp default_name(value, config) do
    case trim_to_nil(value) do
      nil -> config.anonymous
      trimmed -> trimmed
    end
  end

  defp normalize_tripcode(attrs, config) do
    case trim_to_nil(Map.get(attrs, "name")) do
      nil ->
        Map.put(attrs, "tripcode", nil)

      value ->
        {display_name, tripcode} = Tripcode.split_name_and_tripcode(value, config)

        attrs
        |> Map.put("name", display_name)
        |> Map.put("tripcode", tripcode)
    end
  end

  defp normalize_email(nil), do: nil

  defp normalize_email(value),
    do: value |> String.trim() |> String.replace(" ", "%20") |> blank_to_nil()

  defp normalize_post_tag(attrs, %{allowed_tags: allowed_tags}, true) when is_map(allowed_tags) do
    case Map.get(attrs, "tag") do
      nil ->
        {:ok, Map.put(attrs, "tag", nil)}

      tag ->
        normalized_tag = tag |> to_string() |> String.trim()

        {:ok,
         Map.put(
           attrs,
           "tag",
           if(Map.has_key?(allowed_tags, normalized_tag), do: normalized_tag, else: nil)
         )}
    end
  end

  defp normalize_post_tag(attrs, _config, _op?), do: {:ok, Map.put(attrs, "tag", nil)}

  defp normalize_proxy(attrs, %{proxy_save: true}, request) do
    proxy =
      (request[:forwarded_for] || request["forwarded_for"])
      |> case do
        nil -> nil
        value -> value |> to_string() |> sanitize_forwarded_for()
      end

    {:ok, Map.put(attrs, "proxy", proxy)}
  end

  defp normalize_proxy(attrs, _config, _request), do: {:ok, Map.put(attrs, "proxy", nil)}

  defp normalize_moderator_metadata(attrs, request) do
    _ = request
    {:ok, attrs}
  end

  defp sanitize_forwarded_for(value) do
    ipv4s = Regex.scan(~r/\b(?:\d{1,3}\.){3}\d{1,3}\b/u, value) |> List.flatten()

    ipv6s =
      Regex.scan(~r/\b(?:[0-9a-fA-F]{0,4}:){2,}[0-9a-fA-F:]{0,4}\b/u, value) |> List.flatten()

    (ipv4s ++ ipv6s)
    |> Enum.uniq()
    |> Enum.join(", ")
    |> trim_to_nil()
  end

  defp put_request_ip(attrs, request) do
    case Map.get(request, :remote_ip) || Map.get(request, "remote_ip") do
      nil -> attrs
      ip -> Map.put(attrs, "ip_subnet", normalize_request_ip(ip))
    end
  end

  defp normalize_request_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp normalize_request_ip({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp normalize_request_ip(ip) when is_binary(ip), do: String.trim(ip)
  defp normalize_request_ip(_ip), do: nil

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp trim_to_nil(nil), do: nil

  defp trim_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
