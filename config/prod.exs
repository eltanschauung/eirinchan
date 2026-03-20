import Config

config :eirinchan, EirinchanWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto], hsts: true]

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
