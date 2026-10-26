defmodule Eirinchan.Command do
  @moduledoc false

  @default_timeout_ms 15_000
  @imagemagick_commands ~w(convert identify mogrify)
  @imagemagick_environment [
    {"MAGICK_MEMORY_LIMIT", "256MiB"},
    {"MAGICK_MAP_LIMIT", "512MiB"},
    {"MAGICK_DISK_LIMIT", "1GiB"},
    {"MAGICK_AREA_LIMIT", "128MP"},
    {"MAGICK_THREAD_LIMIT", "1"}
  ]

  def run(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    case Eirinchan.MediaProcessing.run(fn -> run_bounded(command, args, opts) end) do
      {:error, :media_busy} -> {"Command capacity is busy", 75}
      {:error, _} -> {"Command failed", 127}
      result -> result
    end
  end

  defp run_bounded(command, args, opts) do
    {timeout, opts} = Keyword.pop(opts, :timeout, configured_timeout())
    timeout = if is_integer(timeout) and timeout > 0, do: min(timeout, 60_000), else: 1

    {limit, opts} =
      Keyword.pop(
        opts,
        :max_output_bytes,
        Eirinchan.Settings.effective_instance_config().external_command_max_output_bytes
      )

    limit = if is_integer(limit) and limit > 0, do: min(limit, 16_777_216), else: 262_144

    opts =
      Keyword.update(opts, :env, resource_environment(command), &merge_environment(command, &1))

    opts = Keyword.put(opts, :into, %Eirinchan.CommandOutput{limit: limit})

    args =
      if Path.basename(command) == "ffmpeg",
        do: ["-threads", "1", "-filter_threads", "1", "-filter_complex_threads", "1" | args],
        else: args

    # GNU timeout owns the process group and kills descendants even when the
    # requester disconnects. No shell interpolation and no unbounded fallback.
    with executable when is_binary(executable) <- System.find_executable(command),
         timeout_executable when is_binary(timeout_executable) <-
           System.find_executable("timeout") do
      duration = Float.to_string(timeout / 1_000) <> "s"

      case System.cmd(
             timeout_executable,
             ["--signal=TERM", "--kill-after=1s", duration, executable | args],
             opts
           ) do
        {{_output, _truncated}, status} when status in [124, 137] ->
          {"Command timed out after #{timeout}ms", 124}

        {{_output, true}, _status} ->
          {"Command output exceeded #{limit} bytes", 125}

        {{output, false}, status} ->
          {output, status}
      end
    else
      _ -> {"Command executable unavailable", 127}
    end
  rescue
    _ -> {"Command failed", 127}
  end

  defp configured_timeout do
    if Map.has_key?(Eirinchan.Settings.current_instance_config(), :external_command_timeout_ms),
      do: Eirinchan.Settings.effective_instance_config().external_command_timeout_ms,
      else: Application.get_env(:eirinchan, :external_command_timeout_ms, @default_timeout_ms)
  end

  defp resource_environment(command) do
    if Path.basename(command) in @imagemagick_commands, do: @imagemagick_environment, else: []
  end

  defp merge_environment(command, configured) do
    resource_environment(command)
    |> Map.new()
    |> Map.merge(Map.new(configured))
    |> Map.to_list()
  end
end
