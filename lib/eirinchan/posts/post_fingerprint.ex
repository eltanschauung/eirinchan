defmodule Eirinchan.Posts.PostFingerprint do
  @moduledoc false

  alias Eirinchan.BrowserIdentity
  alias Eirinchan.CredentialHash

  @default_window_minutes 60
  @maximum_window_minutes 525_600

  @spec put(map(), map(), map()) :: map()
  def put(attrs, request, config)
      when is_map(attrs) and is_map(request) and is_map(config) do
    if window_minutes(config) > 0 do
      case identity(request) do
        identity when is_binary(identity) ->
          attrs
          |> Map.put("duplicate_post_fingerprint", fingerprint(attrs))
          |> Map.put("duplicate_post_identity", identity)

        _ ->
          delete_fingerprint(attrs)
      end
    else
      delete_fingerprint(attrs)
    end
  end

  def put(attrs, _request, _config) when is_map(attrs), do: delete_fingerprint(attrs)

  @spec fingerprint(map()) :: String.t()
  def fingerprint(attrs) when is_map(attrs) do
    payload =
      {:duplicate_post_fingerprint_v1, attrs |> Map.get("body") |> canonical_text(),
       attrs |> Map.get("embed") |> canonical_text(), upload_digests(attrs)}

    payload
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec window_minutes(map()) :: non_neg_integer()
  def window_minutes(config) when is_map(config) do
    case Map.get(config, :duplicate_post_window_minutes, @default_window_minutes) do
      minutes when is_integer(minutes) and minutes >= 0 ->
        min(minutes, @maximum_window_minutes)

      minutes when is_binary(minutes) ->
        case Integer.parse(minutes) do
          {parsed, ""} when parsed >= 0 -> min(parsed, @maximum_window_minutes)
          _ -> @default_window_minutes
        end

      _ ->
        @default_window_minutes
    end
  end

  defp identity(request) do
    browser_ref = Map.get(request, :browser_ref, Map.get(request, "browser_ref"))

    source =
      case browser_ref do
        value when is_binary(value) and value != "" ->
          "browser:" <> BrowserIdentity.reference(value)

        _ ->
          case request_ip(request) do
            value when is_binary(value) and value != "" -> "ip:" <> value
            _ -> nil
          end
      end

    if is_binary(source) do
      CredentialHash.fingerprint(source, :duplicate_post_identity, 43)
    end
  end

  defp request_ip(request) do
    request
    |> Map.get(:remote_ip, Map.get(request, "remote_ip"))
    |> normalize_ip()
  end

  defp normalize_ip({_, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()
  defp normalize_ip({_, _, _, _, _, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()
  defp normalize_ip(value) when is_binary(value), do: String.trim(value)
  defp normalize_ip(_value), do: nil

  defp upload_digests(attrs) do
    attrs
    |> Map.get("__upload_entries__", [])
    |> Enum.map(fn
      %{metadata: metadata} -> Map.get(metadata, :file_md5) || Map.get(metadata, "file_md5")
      _ -> nil
    end)
    |> Enum.map(&canonical_text/1)
    |> Enum.sort()
  end

  defp canonical_text(nil), do: ""

  defp canonical_text(value) when is_binary(value) do
    value
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.trim()
  end

  defp canonical_text(value), do: value |> to_string() |> canonical_text()

  defp delete_fingerprint(attrs) do
    attrs
    |> Map.delete("duplicate_post_fingerprint")
    |> Map.delete(:duplicate_post_fingerprint)
    |> Map.delete("duplicate_post_identity")
    |> Map.delete(:duplicate_post_identity)
  end
end
