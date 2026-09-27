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
# checking engine (MonitorWorker, Checker); incident_id/count/
# retention_days/reason by the alerting and retention Oban workers — so
# every log line is traceable back to what it's actually about.
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :monitor_id,
    :monitor_name,
    :incident_id,
    :reason,
    :count,
    :retention_days
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Hammer (rate limiting) — wired up for real in the API phase; the ETS
# backend needs config to boot even before anything calls it.
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# The checking engine's HTTP client — swapped for a Mox mock in test.
config :pulsewatch, :http_client, Pulsewatch.Monitoring.HttpClient.ReqClient

# The alert worker's webhook client — swapped for a Mox mock in test.
config :pulsewatch, :webhook_client, Pulsewatch.Alerts.WebhookClient.ReqClient

config :pulsewatch, :start_monitors_on_boot, true

config :pulsewatch, Oban,
  engine: Oban.Engines.Basic,
  repo: Pulsewatch.Repo,
  queues: [alerts: 10, maintenance: 1],
  plugins: [
    # Deletes checks older than 30 days, nightly at 03:00 UTC.
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Pulsewatch.Monitoring.PruneChecksWorker}
     ]},
    # Prunes Oban's own completed/cancelled job rows so oban_jobs doesn't
    # grow forever either.
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
