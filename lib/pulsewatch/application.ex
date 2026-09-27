defmodule Pulsewatch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Pulsewatch.Monitoring.MonitorSupervisor

  @impl true
  def start(_type, _args) do
    children = [
      PulsewatchWeb.Telemetry,
      Pulsewatch.Repo,
      {DNSCluster, query: Application.get_env(:pulsewatch, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pulsewatch.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Pulsewatch.Finch},
      {Oban, Application.fetch_env!(:pulsewatch, Oban)},
      # The checking engine: one Registry entry + DynamicSupervisor child
      # per active monitor. A crash in one MonitorWorker only restarts
      # that worker (DynamicSupervisor's default :one_for_one strategy) —
      # it can't take down or affect any other monitor's worker.
      {Registry, keys: :unique, name: Pulsewatch.Monitoring.Registry},
      # Cluster-wide (Postgres-advisory-lock-backed) claim on which node
      # runs which monitor's worker — see its moduledoc for why this
      # exists and why it's advisory locks rather than Horde.
      Pulsewatch.Monitoring.NodeLock,
      MonitorSupervisor,
      # Start to serve requests, typically the last entry
      PulsewatchWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pulsewatch.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      maybe_start_monitors()
      {:ok, pid}
    end
  end

  # Off in :test — the test DB uses Ecto's SQL Sandbox, which requires a
  # test to explicitly check out a connection before any query can run.
  # A query fired here, at application boot before any test has started,
  # would raise DBConnection.OwnershipError. Individual tests call
  # MonitorSupervisor.start_all_active_monitors/0 directly instead, inside
  # their own sandboxed connection.
  defp maybe_start_monitors do
    if Application.get_env(:pulsewatch, :start_monitors_on_boot, true) do
      MonitorSupervisor.start_all_active_monitors()
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PulsewatchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
