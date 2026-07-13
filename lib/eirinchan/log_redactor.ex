defmodule Eirinchan.LogRedactor do
  @moduledoc false

  @filter_id :eirinchan_redact_sensitive_data
  @redacted "[REDACTED]"
  @max_text_length 16_384

  @sensitive_keys ~w(
    authorization
    clearance
    cookie
    csrf
    password
    secret
    session
    token
  )

  def install do
    case :logger.add_primary_filter(@filter_id, {&__MODULE__.filter/2, %{}}) do
      :ok -> :ok
      {:error, {:already_exist, @filter_id}} -> :ok
      {:error, {:already_exists, @filter_id}} -> :ok
      _ -> :ok
    end
  end

  def filter(event, _config) when is_map(event) do
    event
    |> Map.update(:msg, nil, &sanitize_message/1)
    |> Map.update(:meta, %{}, &sanitize_value/1)
  rescue
    _ -> event |> Map.put(:msg, {:string, @redacted <> " LOG EVENT"}) |> Map.put(:meta, %{})
  end

  def sanitize_metadata(metadata) when is_map(metadata), do: sanitize_value(metadata)
  def sanitize_metadata(_metadata), do: %{}

  def sanitize_text(value) do
    value
    |> IO.iodata_to_binary()
    |> redact_serialized_headers()
    |> redact_cookie_values()
    |> String.slice(0, @max_text_length)
  rescue
    _ -> @redacted
  end

  defp sanitize_message({:string, text}), do: {:string, sanitize_text(text)}
  defp sanitize_message({:report, report}), do: {:report, sanitize_value(report)}

  defp sanitize_message({format, arguments}) when is_list(arguments) do
    {sanitize_text(to_string(format)), sanitize_value(arguments)}
  end

  defp sanitize_message(other), do: sanitize_value(other)

  defp sanitize_value(%Plug.Conn{}), do: @redacted <> " Plug.Conn"

  defp sanitize_value(%_{} = struct) do
    struct
    |> inspect(limit: 20, printable_limit: 2_048, width: 120)
    |> sanitize_text()
  end

  defp sanitize_value(value) when is_map(value) do
    value
    |> Enum.take(100)
    |> Map.new(fn {key, nested} ->
      if sensitive_key?(key), do: {key, @redacted}, else: {key, sanitize_value(nested)}
    end)
  end

  defp sanitize_value({key, value}) when is_binary(key) or is_atom(key) do
    if sensitive_key?(key), do: {key, @redacted}, else: {key, sanitize_value(value)}
  end

  defp sanitize_value(value) when is_tuple(value) do
    value |> Tuple.to_list() |> sanitize_value() |> List.to_tuple()
  end

  defp sanitize_value(value) when is_list(value) do
    if List.ascii_printable?(value) do
      sanitize_text(value)
    else
      value |> Enum.take(100) |> Enum.map(&sanitize_value/1)
    end
  end

  defp sanitize_value(value) when is_binary(value), do: sanitize_text(value)
  defp sanitize_value(value), do: value

  defp sensitive_key?(key) do
    normalized = key |> to_string() |> String.downcase()
    Enum.any?(@sensitive_keys, &String.contains?(normalized, &1))
  end

  defp redact_serialized_headers(text) do
    text =
      Regex.replace(
        ~r/(?i)(["']?(?:cookie|set-cookie|authorization|proxy-authorization)["']?\s*(?:=>|:)\s*["'])[^"'\r\n]*/u,
        text,
        "\\1#{@redacted}"
      )

    Regex.replace(
      ~r/(?i)(["'](?:cookie|set-cookie|authorization|proxy-authorization)["']\s*,\s*["'])[^"'\r\n]*/u,
      text,
      "\\1#{@redacted}"
    )
  end

  defp redact_cookie_values(text) do
    text =
      Regex.replace(
        ~r/(?i)((?:_eirinchan_key|cf_clearance|password|session)[^=;\s"']*=)[^;\s,"'}]+/u,
        text,
        "\\1#{@redacted}"
      )

    Regex.replace(
      ~r/(?i)(["'](?:_eirinchan_key|cf_clearance|password|session)[^"']*["']\s*=>\s*["'])[^"']*/u,
      text,
      "\\1#{@redacted}"
    )
  end
end
