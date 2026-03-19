defmodule EirinchanWeb.ManageSecurity do
  alias Eirinchan.Moderation.ModUser

  def generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end

  def session_fingerprint(%ModUser{} = user) do
    secret = endpoint_secret_key_base()
    payload =
      Enum.join(
        [
          user.id,
          user.password_hash || "",
          user.role || "",
          session_login_timestamp(user)
        ],
        ":"
      )

    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.url_encode64(padding: false)
  end

  def ip_fingerprint(remote_ip) when is_tuple(remote_ip) do
    :inet.ntoa(remote_ip) |> to_string()
  end

  def ip_fingerprint(remote_ip) when is_binary(remote_ip), do: remote_ip
  def ip_fingerprint(_remote_ip), do: nil

  def current_session_issued_at do
    System.system_time(:second)
  end

  def session_expired?(issued_at, last_seen_at, config) do
    now = current_session_issued_at()
    idle_limit = max(Map.get(config, :mod_session_idle_minutes, 120), 1) * 60
    absolute_limit = max(Map.get(config, :mod_session_max_hours, 12), 1) * 60 * 60

    expired_absolute?(issued_at, now, absolute_limit) or
      expired_idle?(last_seen_at, now, idle_limit)
  end

  def refresh_session_activity?(last_seen_at) when is_integer(last_seen_at) do
    current_session_issued_at() - last_seen_at >= 60
  end

  def refresh_session_activity?(_), do: true

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

  defp session_login_timestamp(%ModUser{last_login_at: %DateTime{} = value}),
    do: DateTime.to_unix(value)

  defp session_login_timestamp(%ModUser{last_login_at: value}) when is_struct(value, NaiveDateTime),
    do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp session_login_timestamp(_user), do: 0

  defp expired_absolute?(issued_at, now, absolute_limit) when is_integer(issued_at),
    do: now - issued_at > absolute_limit

  defp expired_absolute?(_, _, _), do: true

  defp expired_idle?(last_seen_at, now, idle_limit) when is_integer(last_seen_at),
    do: now - last_seen_at > idle_limit

  defp expired_idle?(_, _, _), do: true
end
