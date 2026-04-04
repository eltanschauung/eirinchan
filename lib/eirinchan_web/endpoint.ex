defmodule EirinchanWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :eirinchan

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_eirinchan_key",
    signing_salt: "3xPU2tNX",
    encryption_salt: "YKr0Mq0s",
    http_only: true,
    secure: Mix.env() == :prod,
    same_site: "Lax"
  ]

  # socket "/live", Phoenix.LiveView.Socket,
  #   websocket: [connect_info: [session: @session_options]],
  #   longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.RequestId
  plug EirinchanWeb.Plugs.AccessLog

  plug Plug.Static,
    at: "/",
    from: :eirinchan,
    gzip: false,
    headers: {EirinchanWeb.CacheControl, :static_headers, []},
    only: EirinchanWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :eirinchan
  end

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: 50_000_000,
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug EirinchanWeb.Plugs.PublicDocumentCache
  plug EirinchanWeb.Plugs.IpAccessAuthRewrite
  plug EirinchanWeb.Router
end
