defmodule Pulsewatch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PulsewatchWeb.Telemetry,
      Pulsewatch.Repo,
      {DNSCluster, query: Application.get_env(:pulsewatch, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pulsewatch.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Pulsewatch.Finch},
      # Start a worker by calling: Pulsewatch.Worker.start_link(arg)
      # {Pulsewatch.Worker, arg},
      # Start to serve requests, typically the last entry
      PulsewatchWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pulsewatch.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PulsewatchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
