defmodule Eirinchan.LogSystem do
  @moduledoc """
  Minimal vichan-style log backend abstraction.
  """

  require Logger

  @spec log(atom(), binary(), binary(), map(), map()) :: :ok
  def log(level, event, message, metadata, config \\ %{}) do
    log_config = Map.get(config, :log_system, %{})
    rendered = render_line(level, event, message, metadata)

    case Map.get(log_config, :type, "error_log") do
      "file" ->
        write_file(Map.get(log_config, :file_path, "/var/log/vichan.log"), rendered)

      "stderr" ->
        IO.write(:stderr, rendered)

      "syslog" ->
        maybe_write_syslog(rendered, log_config)

      _ ->
        Logger.log(level, String.trim_trailing(rendered))
    end

    :ok
  end

  def exception(level, event, exception, stacktrace, metadata, config \\ %{}) do
    log(
      level,
      event,
      Exception.message(exception),
      Map.merge(metadata, %{
        exception: inspect(exception),
        stacktrace: Exception.format_stacktrace(stacktrace)
      }),
      config
    )
  end

  defp render_line(level, event, message, metadata) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    case Map.get(metadata, :log_format) || Map.get(metadata, "log_format") do
      "json" ->
        Jason.encode!(%{
          timestamp: timestamp,
          level: Atom.to_string(level),
          event: event,
          message: message,
          metadata: stringify_metadata(metadata)
        }) <> "\n"

      _ ->
        parts = [timestamp, Atom.to_string(level), event, message | render_metadata(metadata)]
        Enum.join(parts, " ") <> "\n"
    end
  end

  defp render_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.reject(fn {key, _value} -> to_string(key) == "log_format" end)
    |> Enum.map(fn {key, value} -> "#{key}=#{metadata_value(value)}" end)
  end

  defp stringify_metadata(metadata) do
    metadata
    |> Enum.reject(fn {key, _value} -> to_string(key) == "log_format" end)
    |> Map.new(fn {key, value} -> {to_string(key), json_metadata_value(value)} end)
  end

  defp metadata_value(value) when is_binary(value), do: value
  defp metadata_value(value) when is_atom(value), do: Atom.to_string(value)
  defp metadata_value(value), do: inspect(value)

  defp json_metadata_value(value) when is_binary(value), do: value
  defp json_metadata_value(value) when is_integer(value), do: value
  defp json_metadata_value(value) when is_float(value), do: value
  defp json_metadata_value(value) when is_boolean(value), do: value
  defp json_metadata_value(nil), do: nil
  defp json_metadata_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_metadata_value(value) when is_map(value), do: stringify_json_map(value)
  defp json_metadata_value(value) when is_list(value), do: Enum.map(value, &json_metadata_value/1)
  defp json_metadata_value(value), do: inspect(value)

  defp stringify_json_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), json_metadata_value(nested)} end)
  end

  defp write_file(path, line) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    _ = File.write(path, line, [:append])
    :ok
  end

  defp maybe_write_syslog(line, log_config) do
    if Map.get(log_config, :syslog_stderr, false) do
      IO.write(:stderr, line)
    end

    case System.find_executable("logger") do
      nil ->
        Logger.warning(String.trim_trailing(line))

      executable ->
        _ =
          System.cmd(
            executable,
            ["-t", Map.get(log_config, :name, "tinyboard"), String.trim(line)],
            stderr_to_stdout: true
          )

        :ok
    end
  end
end
