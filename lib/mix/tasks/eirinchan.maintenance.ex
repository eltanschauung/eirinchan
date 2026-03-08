defmodule Mix.Tasks.Eirinchan.Maintenance do
  use Mix.Task

  @shortdoc "Runs eirinchan maintenance tasks"

  alias Eirinchan.{Maintenance, Runtime.Config, Settings}

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    config =
      Config.compose(nil, Settings.current_instance_config(), %{}, request_host: "localhost")

    case Maintenance.run(config) do
      {:ok, result} ->
        Mix.shell().info("bans=#{result.bans} antispam=#{result.antispam}")

      {:error, reason} ->
        Mix.raise("maintenance failed: #{inspect(reason)}")
    end
  end
end
