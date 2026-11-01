defmodule Eirinchan.ClientMetadata do
  @moduledoc false

  def user_agent(value) when is_binary(value) do
    if String.valid?(value) do
      value = String.trim(value)
      if byte_size(value) in 1..1024 and not Regex.match?(~r/[\x00-\x1f\x7f]/, value), do: value
    end
  end

  def user_agent(_), do: nil

  def country_code(request, config) do
    supplied = Map.get(request, :country_code)

    result =
      if is_binary(supplied),
        do: {:ok, %{code: supplied}},
        else:
          Eirinchan.GeoIp.lookup_country(
            EirinchanWeb.RequestMeta.ip_to_string(request[:remote_ip]),
            config
          )

    case result do
      {:ok, %{code: code}} when is_binary(code) ->
        code = String.downcase(code)
        if Regex.match?(~r/\A[a-z]{2}\z/, code), do: code

      _ ->
        nil
    end
  end
end
