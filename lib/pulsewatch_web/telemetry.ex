defmodule PulsewatchWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("pulsewatch.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("pulsewatch.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("pulsewatch.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("pulsewatch.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("pulsewatch.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Checking engine, alerting, and AI summary metrics — see
      # Pulsewatch.Monitoring.Checker, Pulsewatch.Alerts.IncidentAlertWorker,
      # and Pulsewatch.Ai.IncidentSummaryWorker for where these are emitted.
      summary("pulsewatch.monitor.check.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status],
        description: "Duration of a single monitor check, by result (:up/:down)"
      ),
      counter("pulsewatch.monitor.check.stop.count",
        tags: [:status],
        description: "Number of monitor checks performed, by result"
      ),
      counter("pulsewatch.alert.sent.count",
        tags: [:channel, :result],
        description: "Alert notifications sent, by channel (:email/:webhook) and result"
      ),
      summary("pulsewatch.llm.stop.duration",
        unit: {:native, :millisecond},
        tags: [:result],
        description: "Duration of an LLM call for an incident summary"
      ),
      counter("pulsewatch.llm.stop.count",
        tags: [:result],
        description: "LLM calls made for incident summaries, by result"
      )
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {PulsewatchWeb, :count_users, []}
    ]
  end
end
