defmodule Eirinchan.Posts.ThreadFingerprint do
  @moduledoc false

  @fingerprint_fields ~w(subject body embed tag)

  @spec put(map(), Eirinchan.Posts.Post.t() | nil, map()) :: map()
  def put(attrs, nil, config) when is_map(attrs) and is_map(config) do
    if window_hours(config) > 0 do
      Map.put(attrs, "thread_fingerprint", fingerprint(attrs))
    else
      delete_fingerprint(attrs)
    end
  end

  def put(attrs, _thread, _config) when is_map(attrs), do: delete_fingerprint(attrs)

  @spec fingerprint(map()) :: String.t()
  def fingerprint(attrs) when is_map(attrs) do
    payload =
      {:thread_fingerprint_v1,
       Enum.map(@fingerprint_fields, fn field ->
         {field, attrs |> Map.get(field) |> canonical_text()}
       end), upload_digests(attrs)}

    payload
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec window_hours(map()) :: non_neg_integer()
  def window_hours(config) when is_map(config) do
    case Map.get(config, :duplicate_thread_window_hours, 24) do
      hours when is_integer(hours) and hours >= 0 ->
        hours

      hours when is_binary(hours) ->
        case Integer.parse(hours) do
          {parsed, ""} when parsed >= 0 -> parsed
          _ -> 24
        end

      _ ->
        24
    end
  end

  defp upload_digests(attrs) do
    attrs
    |> Map.get("__upload_entries__", [])
    |> Enum.map(fn
      %{metadata: metadata} -> Map.get(metadata, :file_md5) || Map.get(metadata, "file_md5")
      _ -> nil
    end)
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
    |> Map.delete("thread_fingerprint")
    |> Map.delete(:thread_fingerprint)
  end
end
