import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pulsewatch, Pulsewatch.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pulsewatch_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pulsewatch, PulsewatchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "zFuluReudohnumtO15fCAlOY/DuEQ3shxW4vIEJoPSMRlHxeLR0c1RbWvgjAgJs3",
  server: false

# In test we don't send emails
config :pulsewatch, Pulsewatch.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# The checking engine's HTTP client is Mox-mocked in tests — nothing in
# the suite ever makes a real network call for a monitor check.
config :pulsewatch, :http_client, Pulsewatch.Monitoring.HttpClientMock

# Same story for the alert worker's webhook client.
config :pulsewatch, :webhook_client, Pulsewatch.Alerts.WebhookClientMock

# See Pulsewatch.Application for why: booting workers at application
# start requires a DB connection the SQL Sandbox hasn't granted yet.
config :pulsewatch, :start_monitors_on_boot, false

# Oban.Testing's :manual mode — jobs are inserted into the database (so
# uniqueness/scheduling logic still runs for real) but never picked up by
# a real queue. Tests trigger perform/1 explicitly via Oban.Testing's
# perform_job/2,3 or assert on what got enqueued via assert_enqueued/1.
config :pulsewatch, Oban, testing: :manual
