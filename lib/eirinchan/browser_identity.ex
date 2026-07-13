defmodule Eirinchan.BrowserIdentity do
  @moduledoc false

  alias Eirinchan.CredentialHash

  @version "v1"
  @token_bytes 24
  @encoded_token_size 32
  @encoded_signature_size 43
  @clock_skew_seconds 300
  @reference_prefix "browser-ref:v1:"
  @reference_size byte_size(@reference_prefix) + @encoded_signature_size
  @client_prefix "client-ref:v1:"

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

  def reference(@reference_prefix <> digest = reference)
      when byte_size(reference) == @reference_size and
             byte_size(digest) == @encoded_signature_size do
    case Base.url_decode64(digest, padding: false) do
      {:ok, decoded} when byte_size(decoded) == 32 -> reference
      _ -> hash_reference(reference)
    end
  end

  def reference(token) when is_binary(token), do: hash_reference(token)

  def reference?(@reference_prefix <> digest = reference)
      when byte_size(reference) == @reference_size and
             byte_size(digest) == @encoded_signature_size do
    match?(
      {:ok, decoded} when byte_size(decoded) == 32,
      Base.url_decode64(digest, padding: false)
    )
  end

  def reference?(_value), do: false

  def client_reference(ip_subnet, browser_ref)
      when is_binary(ip_subnet) and is_binary(browser_ref) do
    @client_prefix <>
      CredentialHash.fingerprint(
        ip_subnet <> <<0>> <> reference(browser_ref),
        :browser_identity_client,
        @encoded_signature_size
      )
  end

  defp signature(payload) do
    CredentialHash.fingerprint(payload, :browser_identity_cookie, @encoded_signature_size)
  end

  defp hash_reference(token) do
    @reference_prefix <>
      CredentialHash.fingerprint(token, :browser_identity_reference, @encoded_signature_size)
  end
end
