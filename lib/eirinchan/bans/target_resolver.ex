defmodule Eirinchan.Bans.TargetResolver do
  @moduledoc false

  alias Eirinchan.IpCrypt
  alias Eirinchan.IpMatching

  @type error :: {:error, :invalid_target}

  @spec resolve(term()) :: {:ok, String.t()} | error()
  def resolve(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" ->
        {:error, :invalid_target}

      target ->
        if String.contains?(target, "/"), do: resolve_cidr(target), else: resolve_ip(target)
    end
  end

  def resolve(_value), do: {:error, :invalid_target}

  @spec resolve_ip(term()) :: {:ok, String.t()} | error()
  def resolve_ip(value) when is_binary(value) do
    candidate = String.trim(value)

    with false <- candidate == "",
         decoded when is_binary(decoded) <- decode_ip(candidate),
         normalized when not is_nil(normalized) <- IpMatching.normalize_ip(decoded) do
      {:ok, format_ip(normalized)}
    else
      _ -> {:error, :invalid_target}
    end
  end

  def resolve_ip(_value), do: {:error, :invalid_target}

  @spec normalize_for_storage(term()) :: term()
  def normalize_for_storage(value) do
    case resolve(value) do
      {:ok, target} -> target
      {:error, :invalid_target} -> trim_if_binary(value)
    end
  end

  defp resolve_cidr(candidate) do
    with [address, prefix] <- String.split(candidate, "/", parts: 2),
         {prefix_size, ""} <- Integer.parse(String.trim(prefix)),
         normalized when not is_nil(normalized) <- IpMatching.normalize_ip(String.trim(address)),
         true <- prefix_size >= 0 and prefix_size <= address_bits(normalized) do
      {:ok, "#{format_ip(normalized)}/#{prefix_size}"}
    else
      _ -> {:error, :invalid_target}
    end
  end

  defp decode_ip(candidate) do
    case IpMatching.normalize_ip(candidate) do
      nil -> IpCrypt.uncloak_ip(candidate)
      _normalized -> candidate
    end
  end

  defp format_ip({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  defp format_ip({a, b, c, d, e, f, g, h}) do
    :inet.ntoa({a, b, c, d, e, f, g, h}) |> to_string()
  end

  defp address_bits({_a, _b, _c, _d}), do: 32
  defp address_bits({_a, _b, _c, _d, _e, _f, _g, _h}), do: 128

  defp trim_if_binary(value) when is_binary(value), do: String.trim(value)
  defp trim_if_binary(value), do: value
end
