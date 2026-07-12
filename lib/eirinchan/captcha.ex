defmodule Eirinchan.Captcha do
  @moduledoc false

  @providers %{
    "native" => "captcha",
    "recaptcha" => "g-recaptcha-response",
    "hcaptcha" => "h-captcha-response"
  }

  def verify(config, params, request) do
    captcha = Map.get(config, :captcha, %{})
    provider = Map.get(captcha, :provider, "native")
    field = field(provider)
    response = params[field] |> to_string() |> String.trim()

    case provider do
      "native" -> verify_native(captcha, response)
      "recaptcha" -> verify_remote(captcha, response, request)
      "hcaptcha" -> verify_remote(captcha, response, request)
      _ -> verify_native(captcha, response)
    end
  end

  def field(provider), do: Map.get(@providers, provider, "captcha")

  defp verify_native(captcha, response) do
    expected = Map.get(captcha, :expected_response)

    if expected && response != "" && response == expected do
      :ok
    else
      {:error, :invalid_captcha}
    end
  end

  defp verify_remote(captcha, response, request) do
    cond do
      response == "" ->
        {:error, :invalid_captcha}

      is_binary(captcha[:verify_url]) and captcha[:verify_url] != "" ->
        remote_verify(captcha, response, request)

      true ->
        verify_native(captcha, response)
    end
  end

  defp remote_verify(captcha, response, request) do
    body =
      URI.encode_query(%{
        "secret" => to_string(captcha[:secret] || ""),
        "response" => response,
        "remoteip" => remote_ip_string(request[:remote_ip] || request["remote_ip"]) || ""
      })

    headers = [{~c"content-type", ~c"application/x-www-form-urlencoded"}]
    timeout = captcha[:http_timeout_ms] || 5_000

    case :httpc.request(
           :post,
           {to_charlist(captcha[:verify_url]), headers, ~c"application/x-www-form-urlencoded",
            body},
           [timeout: timeout, connect_timeout: timeout],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _headers, response_body}} ->
        parse_verify_response(response_body)

      _ ->
        {:error, :invalid_captcha}
    end
  end

  defp parse_verify_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"success" => true}} -> :ok
      {:ok, %{success: true}} -> :ok
      _ -> {:error, :invalid_captcha}
    end
  rescue
    _ -> {:error, :invalid_captcha}
  end

  defp remote_ip_string({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp remote_ip_string({a, b, c, d, e, f, g, h}) do
    Enum.map_join([a, b, c, d, e, f, g, h], ":", &Integer.to_string(&1, 16))
  end

  defp remote_ip_string(value) when is_binary(value), do: String.trim(value)
  defp remote_ip_string(_value), do: nil
end
