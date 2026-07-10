defmodule Eirinchan.MaintenanceWorker do
  @moduledoc false

  use GenServer

  require Logger

  alias Eirinchan.Maintenance
  alias Eirinchan.Settings

  @minimum_interval_ms 60_000
  @maximum_interval_ms 60 * 60 * 1_000

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def run_now(server \\ __MODULE__), do: GenServer.call(server, :run, 60_000)

  @impl true
  def init(opts) do
    state = %{
      repo: Keyword.get(opts, :repo, Eirinchan.Repo),
      config_provider: Keyword.get(opts, :config_provider, &Settings.current_instance_config/0)
    }

    schedule(Keyword.get(opts, :initial_delay_ms, 5_000))
    {:ok, state}
  end

  @impl true
  def handle_call(:run, _from, state) do
    {:reply, run_maintenance(state), state}
  end

  @impl true
  def handle_info(:run, state) do
    config = state.config_provider.()
    _ = safe_run(config, state.repo)
    schedule(next_interval(config))
    {:noreply, state}
  end

  defp run_maintenance(state) do
    config = state.config_provider.()
    safe_run(config, state.repo)
  end

  defp safe_run(config, repo) do
    Maintenance.run_if_due(config, repo: repo)
  rescue
    error ->
      Logger.error("scheduled maintenance failed: #{Exception.message(error)}")
      {:error, error}
  end

  defp next_interval(config) do
    config
    |> Map.get(:maintenance_interval_seconds, 12 * 60 * 60)
    |> max(60)
    |> Kernel.*(1_000)
    |> min(@maximum_interval_ms)
    |> max(@minimum_interval_ms)
  end

  defp schedule(delay_ms), do: Process.send_after(self(), :run, delay_ms)
end
