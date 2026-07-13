defmodule Eirinchan.BrowserIdentity do
  @moduledoc false

  alias Eirinchan.CredentialHash

  @version "v1"
  @token_bytes 24
  @encoded_token_size 32
  @encoded_signature_size 43
  @clock_skew_seconds 300

  def generate_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  def issue(token \\ generate_token(), issued_at \\ System.system_time(:second))

  def issue(token, issued_at) when is_integer(issued_at) and issued_at >= 0 do
    if valid_token?(token) do
      payload = Enum.join([@version, Integer.to_string(issued_at), token], ".")
      payload <> "." <> signature(payload)
    else
      raise ArgumentError, "browser identity token must be 32 base64url characters"
    end
  end

  def verify(value, now \\ System.system_time(:second))

  def verify(value, now) when is_binary(value) and is_integer(now) do
    with [@version, issued_at_string, token, supplied_signature] <- String.split(value, "."),
         {issued_at, ""} <- Integer.parse(issued_at_string),
         true <- issued_at >= 0 and issued_at <= now + @clock_skew_seconds,
         true <- valid_token?(token),
         true <- byte_size(supplied_signature) == @encoded_signature_size do
      payload = Enum.join([@version, issued_at_string, token], ".")

      if Plug.Crypto.secure_compare(signature(payload), supplied_signature) do
        {:ok, %{token: token, issued_at: issued_at}}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  def verify(_value, _now), do: :error

  def valid_token?(token) when is_binary(token) and byte_size(token) == @encoded_token_size do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} -> byte_size(decoded) == @token_bytes
      :error -> false
    end
  end

  def valid_token?(_token), do: false

  defp signature(payload) do
    CredentialHash.fingerprint(payload, :browser_identity_cookie, @encoded_signature_size)
  end
end
