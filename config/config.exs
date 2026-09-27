# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pulsewatch,
  ecto_repos: [Pulsewatch.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :pulsewatch, PulsewatchWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PulsewatchWeb.ErrorHTML, json: PulsewatchWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Pulsewatch.PubSub,
  live_view: [signing_salt: "wJEz0Afj"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :pulsewatch, Pulsewatch.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  pulsewatch: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  pulsewatch: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger. monitor_id/monitor_name are set by the
# checking engine (MonitorWorker, Checker) so every log line from a check
# is traceable back to the monitor it came from.
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :monitor_id, :monitor_name]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Hammer (rate limiting) — wired up for real in the API phase; the ETS
# backend needs config to boot even before anything calls it.
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# The checking engine's HTTP client — swapped for a Mox mock in test.
config :pulsewatch, :http_client, Pulsewatch.Monitoring.HttpClient.ReqClient

config :pulsewatch, :start_monitors_on_boot, true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
