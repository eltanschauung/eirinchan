defmodule Eirinchan.CredentialHash do
  @moduledoc false

  @prefix "hmac-sha256:v1:"

  def hash(value, purpose) when is_binary(value) do
    digest =
      :crypto.mac(
        :hmac,
        :sha256,
        secret_key_base(),
        IO.iodata_to_binary(purpose_data(purpose, value))
      )
    @prefix <> Base.url_encode64(digest, padding: false)
  end

  def verify(value, stored, purpose) when is_binary(value) and is_binary(stored) do
    expected = if encoded?(stored), do: hash(value, purpose), else: value
    secure_compare(expected, stored)
  end

  def verify(_value, _stored, _purpose), do: false

  def encoded?(@prefix <> encoded) when byte_size(encoded) > 0, do: true
  def encoded?(_value), do: false

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp secure_compare(_left, _right), do: false

  defp purpose_data(purpose, value), do: [to_string(purpose), <<0>>, value]

  defp secret_key_base do
    :eirinchan
    |> Application.fetch_env!(EirinchanWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end
end
