defmodule EirinchanWeb.ManageSecurity do
  def generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end

  def sign_action(nil, _value), do: nil

  def sign_action(session_token, value) when is_binary(session_token) do
    :crypto.mac(:hmac, :sha256, session_token, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end

  def valid_action_token?(session_token, value, token)
      when is_binary(session_token) and is_binary(value) and is_binary(token) do
    sign_action(session_token, value) == String.trim(token)
  end

  def valid_action_token?(_, _, _), do: false
end
