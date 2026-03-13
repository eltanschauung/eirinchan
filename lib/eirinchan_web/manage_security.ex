defmodule EirinchanWeb.ManageSecurity do
  alias Eirinchan.Moderation.ModUser

  def generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end

  def session_fingerprint(%ModUser{} = user) do
    secret = endpoint_secret_key_base()
    payload = Enum.join([user.id, user.password_hash || "", user.role || ""], ":")

    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.url_encode64(padding: false)
  end

  def ip_fingerprint(remote_ip) when is_tuple(remote_ip) do
    :inet.ntoa(remote_ip) |> to_string()
  end

  def ip_fingerprint(remote_ip) when is_binary(remote_ip), do: remote_ip
  def ip_fingerprint(_remote_ip), do: nil

  def sign_action(nil, _value), do: nil

  def sign_action(session_token, value) when is_binary(session_token) do
    :crypto.mac(:hmac, :sha256, session_token, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end

  def valid_action_token?(session_token, value, token)
      when is_binary(session_token) and is_binary(value) and is_binary(token) do
    expected = sign_action(session_token, value)
    provided = String.trim(token)

    byte_size(expected) == byte_size(provided) and
      Plug.Crypto.secure_compare(expected, provided)
  end

  def valid_action_token?(_, _, _), do: false

  defp endpoint_secret_key_base do
    EirinchanWeb.Endpoint.config(:secret_key_base) ||
      raise "endpoint secret_key_base is not configured"
  end
end
