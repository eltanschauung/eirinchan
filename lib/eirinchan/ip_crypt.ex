defmodule Eirinchan.IpCrypt do
  @moduledoc false

  alias Eirinchan.IpMatching
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings

  @request_config_key :eirinchan_ipcrypt_config
  @request_viewer_ip_key :eirinchan_ipcrypt_viewer_ip

  @default_config %{
    ipcrypt_key: "",
    ipcrypt_prefix: "Cloak",
    ipcrypt_immune_ip: "0.0.0.0"
  }

  def configure_for_request(config, viewer_ip) when is_map(config) do
    Process.put(@request_config_key, normalize_config(config))
    Process.put(@request_viewer_ip_key, normalize_ip_string(viewer_ip))
    :ok
  end

  def clear_request_context do
    Process.delete(@request_config_key)
    Process.delete(@request_viewer_ip_key)
    :ok
  end

  def cloak_ip(nil), do: nil

  def cloak_ip(ip) when is_binary(ip) do
    value = String.trim(ip)
    cfg = config()

    cond do
      value == "" ->
        value

      immune_viewer?(cfg) ->
        value

      blank?(cfg.ipcrypt_key) ->
        value

      String.starts_with?(value, cfg.ipcrypt_prefix <> ":") ->
        value

      not valid_plain_ip?(value) ->
        value

      true ->
        cfg.ipcrypt_prefix <> ":" <> encrypt_ip(value, cfg.ipcrypt_key)
    end
  end

  def cloak_ip(ip), do: ip |> normalize_ip_string() |> cloak_ip()

  def uncloak_ip(value) when is_binary(value) do
    cfg = config()
    candidate = String.trim(value)

    cond do
      valid_plain_ip?(candidate) ->
        candidate

      blank?(cfg.ipcrypt_key) ->
        candidate

      String.starts_with?(candidate, cfg.ipcrypt_prefix <> ":") ->
        candidate
        |> strip_dns_suffix()
        |> String.replace_prefix(cfg.ipcrypt_prefix <> ":", "")
        |> decrypt_ip(cfg.ipcrypt_key)

      true ->
        nil
    end
  end

  def uncloak_ip(_value), do: nil

  def immune?(ip) do
    cfg = config()
    immune_entry = cfg.ipcrypt_immune_ip |> to_string() |> String.trim()

    not blank?(immune_entry) and immune_entry != "0.0.0.0" and IpMatching.entry_match?(ip, immune_entry)
  end

  def config do
    Process.get(@request_config_key) || fallback_config()
  end

  defp fallback_config do
    Settings.current_instance_config()
    |> Config.normalize_override_keys()
    |> normalize_config()
  end

  defp normalize_config(config) do
    Map.merge(@default_config, %{
      ipcrypt_key: Map.get(config, :ipcrypt_key) || Map.get(config, "ipcrypt_key") || "",
      ipcrypt_prefix: Map.get(config, :ipcrypt_prefix) || Map.get(config, "ipcrypt_prefix") || "Cloak",
      ipcrypt_immune_ip:
        Map.get(config, :ipcrypt_immune_ip) || Map.get(config, "ipcrypt_immune_ip") || "0.0.0.0"
    })
  end

  defp immune_viewer?(cfg) do
    viewer_ip = Process.get(@request_viewer_ip_key)
    immune_entry = cfg.ipcrypt_immune_ip |> to_string() |> String.trim()

    viewer_ip &&
      not blank?(viewer_ip) &&
      not blank?(immune_entry) &&
      immune_entry != "0.0.0.0" &&
      IpMatching.entry_match?(viewer_ip, immune_entry)
  end

  defp encrypt_ip(ip, key) do
    ip
    |> ip_to_binary()
    |> then(&:crypto.crypto_one_time(:aes_256_ctr, encryption_key(key), zero_iv(), &1, true))
    |> Base.encode32(padding: false, case: :upper)
  end

  defp decrypt_ip(encoded, key) do
    with {:ok, ciphertext} <- decode32(encoded),
         plaintext <- :crypto.crypto_one_time(:aes_256_ctr, encryption_key(key), zero_iv(), ciphertext, false),
         {:ok, ip} <- binary_to_ip(plaintext) do
      ip
    else
      _ -> nil
    end
  end

  defp decode32(value) do
    case Base.decode32(value, padding: false, case: :mixed) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> :error
    end
  end

  defp encryption_key(value), do: :crypto.hash(:sha256, value)
  defp zero_iv, do: <<0::128>>

  defp ip_to_binary(value) do
    case IpMatching.parse_ip(value) do
      {:ok, {a, b, c, d}} -> <<a, b, c, d>>
      {:ok, {a, b, c, d, e, f, g, h}} -> <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>
      _ -> raise ArgumentError, "invalid IP"
    end
  end

  defp binary_to_ip(<<a, b, c, d>>) do
    {:ok, Enum.join([a, b, c, d], ".")}
  end

  defp binary_to_ip(<<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>) do
    {:ok, :inet.ntoa({a, b, c, d, e, f, g, h}) |> to_string()}
  end

  defp binary_to_ip(_value), do: :error

  defp strip_dns_suffix(value) do
    case String.split(value, ".", parts: 2) do
      [cloak, _suffix] -> cloak
      [cloak] -> cloak
    end
  end

  defp valid_plain_ip?(value) do
    match?({:ok, _}, IpMatching.parse_ip(String.trim(value)))
  end

  defp normalize_ip_string(nil), do: nil

  defp normalize_ip_string(ip) do
    case IpMatching.normalize_ip(ip) do
      {a, b, c, d} ->
        Enum.join([a, b, c, d], ".")

      {a, b, c, d, e, f, g, h} ->
        :inet.ntoa({a, b, c, d, e, f, g, h}) |> to_string()

      nil ->
        to_string(ip)
    end
  end

  defp blank?(value), do: value in [nil, ""]
end
