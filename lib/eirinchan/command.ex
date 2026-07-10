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
    {timeout, opts} = Keyword.pop(opts, :timeout, configured_timeout())
    opts = Keyword.update(opts, :env, resource_environment(command), &merge_environment(command, &1))
    task = Task.async(fn -> System.cmd(command, args, opts) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {"Command failed: #{inspect(reason)}", 127}
      _timeout -> {"Command timed out after #{timeout}ms", 124}
    end
  end

  defp configured_timeout do
    Application.get_env(:eirinchan, :external_command_timeout_ms, @default_timeout_ms)
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
