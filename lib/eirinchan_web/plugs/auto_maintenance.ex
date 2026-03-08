defmodule EirinchanWeb.Plugs.AutoMaintenance do
  @moduledoc false

  alias Eirinchan.Maintenance
  alias Eirinchan.Runtime.Config
  alias Eirinchan.Settings

  def init(opts), do: opts

  def call(conn, _opts) do
    config =
      Config.compose(nil, Settings.current_instance_config(), %{},
        request_host: EirinchanWeb.RequestMeta.request_host(conn)
      )

    _ = Maintenance.run_if_due(config)
    conn
  end
end
