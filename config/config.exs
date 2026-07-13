# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :eirinchan,
  ecto_repos: [Eirinchan.Repo],
  feedback_store_ip: false,
  ip_access_list: %{enabled: false, entries: []},
  ip_privacy: %{enabled: true, cloak_key: "eirinchan-dev-ip", immune_ips: [], immune_cidrs: []},
  site_assets: %{version: nil, custom_javascript: [], analytics_html: nil},
  allowed_hosts: ["localhost", "www.example.com"],
  external_command_timeout_ms: 15_000,
  quarantine_invalid_uploads: false,
  quarantine_invalid_upload_root: Path.expand("../var/invalid_uploads", __DIR__),
  fragment_cache: [max_entries: 5_000, ttl_ms: 300_000],
  instance_config_path: Path.expand("../var/settings.json", __DIR__),
  proxy_request: %{
    trust_headers: true,
    trusted_ips: ["127.0.0.1", "::1"],
    trusted_cidrs: ["127.0.0.0/8"],
    client_ip_headers: ["x-forwarded-for", "x-real-ip"]
  },
  build_output_root: Path.expand("../tmp/build", __DIR__),
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :eirinchan, EirinchanWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EirinchanWeb.ErrorHTML, json: EirinchanWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Eirinchan.PubSub,
  live_view: [signing_salt: "qltTzb8m"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :remote_ip],
  truncate: 16_384

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
