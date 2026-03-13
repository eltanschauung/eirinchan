defmodule Eirinchan.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Eirinchan.Installation.apply_persisted_repo_config()

    children = [
      EirinchanWeb.Telemetry,
      Eirinchan.Repo,
      {DNSCluster, query: Application.get_env(:eirinchan, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Eirinchan.PubSub},
      EirinchanWeb.FragmentCache,
      # Start a worker by calling: Eirinchan.Worker.start_link(arg)
      # {Eirinchan.Worker, arg},
      # Start to serve requests, typically the last entry
      EirinchanWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eirinchan.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EirinchanWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
