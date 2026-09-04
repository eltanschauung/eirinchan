defmodule Eirinchan.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = Eirinchan.LogRedactor.install()

    children =
      [
        EirinchanWeb.Telemetry,
        Eirinchan.Repo,
        access_log_worker(),
        {DNSCluster, query: Application.get_env(:eirinchan, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Eirinchan.PubSub},
        {Task.Supervisor, name: Eirinchan.BuildTaskSupervisor},
        Eirinchan.VisitorQualification,
        Eirinchan.BrowserPresence,
        Eirinchan.ManageLoginThrottle,
        Eirinchan.IpAccessAuthThrottle,
        Eirinchan.StaticImageDimensions,
        EirinchanWeb.FragmentCache,
        statistics_snapshot_worker(),
        global_message_refresh_worker(),
        maintenance_worker(),
        health_log_worker(),
        EirinchanWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eirinchan.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maintenance_worker do
    if Application.get_env(:eirinchan, :start_maintenance_worker, true),
      do: Eirinchan.MaintenanceWorker
  end

  defp access_log_worker do
    if Application.get_env(:eirinchan, :start_access_log, true), do: Eirinchan.AccessLog
  end

  defp global_message_refresh_worker do
    if Application.get_env(:eirinchan, :start_global_message_refresh_worker, true),
      do: Eirinchan.GlobalMessageRefreshWorker
  end

  defp statistics_snapshot_worker do
    if Application.get_env(:eirinchan, :start_statistics_snapshots, true),
      do: Eirinchan.Statistics.Worker
  end

  defp health_log_worker do
    if Application.get_env(:eirinchan, :start_health_log_worker, true),
      do: Eirinchan.HealthLogWorker
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EirinchanWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
