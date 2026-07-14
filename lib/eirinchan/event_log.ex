defmodule Eirinchan.EventLog do
  @moduledoc false

  require Logger

  alias Eirinchan.CredentialHash
  alias Eirinchan.LogRedactor
  alias EirinchanWeb.RequestMeta

  def log(conn, event, metadata \\ %{}, level \\ :warning)

  def log(%Plug.Conn{} = conn, event, metadata, level)
      when is_binary(event) and is_map(metadata) and level in [:debug, :info, :notice, :warning, :error] do
    payload =
      metadata
      |> Map.merge(%{
        event: event,
        client_id: client_id(conn),
        method: conn.method,
        path: conn.request_path,
        request_id: Logger.metadata()[:request_id]
      })
      |> LogRedactor.sanitize_metadata()
      |> json_value()

    Logger.log(level, fn -> "event " <> Jason.encode!(payload) end)
    :ok
  rescue
    error ->
      Logger.error("failed to encode structured event: #{Exception.message(error)}")
      :error
  end

  def subject_id(value, purpose) when is_atom(purpose) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> CredentialHash.fingerprint(purpose)
  end

  defp client_id(conn) do
    conn
    |> RequestMeta.effective_remote_ip()
    |> RequestMeta.ip_to_string()
    |> CredentialHash.fingerprint(:access_log_ip)
  end

  defp json_value(value) when is_binary(value), do: value
  defp json_value(value) when is_integer(value), do: value
  defp json_value(value) when is_float(value), do: value
  defp json_value(value) when is_boolean(value), do: value
  defp json_value(nil), do: nil
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)

  defp json_value(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), json_value(nested)} end)
  end

  defp json_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_value()
  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)
  defp json_value(value), do: inspect(value, limit: 20, printable_limit: 2_048)
end
