defmodule Pulsewatch.Monitoring.Checker do
  @moduledoc """
  Runs a single check for a monitor: performs the HTTP request, records a
  `Check`, and opens/resolves an `Incident` based on the consecutive
  failure count.

  Deliberately plain, process-free code — it takes the current failure
  count as an argument and returns the new one, rather than owning any
  state itself. That's what makes it testable without starting a
  GenServer: `MonitorWorker` is a thin shell that just does the
  scheduling and holds `consecutive_failures` between calls.
  """

  require Logger

  alias Pulsewatch.Alerts
  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.{Check, Monitor}

  @failure_threshold 2

  @type transition :: :became_down | :became_up | :no_change

  @doc """
  Performs one check for `monitor`, given the number of consecutive
  failures observed so far. Persists a `Check` row and, if the failure
  count crosses (or un-crosses) the down threshold, opens or resolves an
  `Incident`.

  Returns the new consecutive-failure count and what happened, so the
  caller (the worker) can log/track it without duplicating this logic.

  Emits `[:pulsewatch, :monitor, :check, :start | :stop | :exception]` (a
  `:telemetry.span/3`) covering the whole check — HTTP request plus the DB
  writes — tagged with the resulting status, so LiveDashboard can chart
  both check volume and latency broken down by up/down.
  """
  @spec run(Monitor.t(), non_neg_integer()) :: %{
          check: Check.t(),
          consecutive_failures: non_neg_integer(),
          transition: transition()
        }
  def run(%Monitor{} = monitor, consecutive_failures) do
    :telemetry.span([:pulsewatch, :monitor, :check], %{monitor_id: monitor.id}, fn ->
      result = do_run(monitor, consecutive_failures)
      {result, %{monitor_id: monitor.id, status: result.check.status}}
    end)
  end

  defp do_run(monitor, consecutive_failures) do
    {status, response_time_ms, status_code, error_message} = perform_request(monitor)

    {:ok, check} =
      Monitoring.create_check(monitor, %{
        status: status,
        response_time_ms: response_time_ms,
        status_code: status_code,
        error_message: error_message,
        checked_at: DateTime.utc_now()
      })

    {new_failures, transition} = advance(status, consecutive_failures)
    apply_transition(monitor, transition)
    Monitoring.broadcast(monitor, {:check_recorded, check})

    %{check: check, consecutive_failures: new_failures, transition: transition}
  end

  defp perform_request(%Monitor{check_type: :http} = monitor) do
    {result, elapsed} = measure(fn -> http_client().get(monitor.url, monitor.timeout_ms) end)
    interpret_http(result, elapsed, monitor.expected_status_code)
  end

  defp perform_request(%Monitor{check_type: :tcp} = monitor) do
    {result, elapsed} =
      measure(fn -> tcp_client().connect(monitor.host, monitor.port, monitor.timeout_ms) end)

    interpret_tcp(result, elapsed)
  end

  defp measure(fun) do
    started_at = System.monotonic_time(:millisecond)
    result = fun.()
    {result, System.monotonic_time(:millisecond) - started_at}
  end

  defp interpret_http({:ok, status_code}, elapsed, expected_status_code) do
    if status_code == expected_status_code do
      {:up, elapsed, status_code, nil}
    else
      {:down, elapsed, status_code, "unexpected status #{status_code}"}
    end
  end

  # A timeout near timeout_ms and an instant connection refusal are
  # different signals worth keeping, so elapsed time is recorded here
  # too, not just on the success path.
  defp interpret_http({:error, reason}, elapsed, _expected_status_code) do
    {:down, elapsed, nil, format_error(reason)}
  end

  # No status code or response body for a TCP check — a successful
  # connect is the entire signal.
  defp interpret_tcp(:ok, elapsed), do: {:up, elapsed, nil, nil}
  defp interpret_tcp({:error, reason}, elapsed), do: {:down, elapsed, nil, format_error(reason)}

  defp format_error(reason) when is_exception(reason), do: Exception.message(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  @spec advance(:up | :down, non_neg_integer()) :: {non_neg_integer(), transition()}
  defp advance(:up, consecutive_failures) when consecutive_failures >= @failure_threshold,
    do: {0, :became_up}

  defp advance(:up, _consecutive_failures), do: {0, :no_change}

  defp advance(:down, consecutive_failures) do
    new_failures = consecutive_failures + 1

    if new_failures == @failure_threshold do
      {new_failures, :became_down}
    else
      {new_failures, :no_change}
    end
  end

  defp apply_transition(monitor, :became_down) do
    case Monitoring.get_open_incident(monitor) do
      # Already open (e.g. a race with another check) — stay idempotent.
      {:ok, _incident} ->
        :ok

      {:error, :not_found} ->
        {:ok, incident} = Alerts.open_incident(monitor)
        Logger.warning("monitor down", monitor_id: monitor.id, monitor_name: monitor.name)
        Monitoring.broadcast(monitor, {:incident_opened, incident})
        :ok
    end
  end

  defp apply_transition(monitor, :became_up) do
    case Monitoring.get_open_incident(monitor) do
      {:ok, incident} ->
        {:ok, resolved} = Alerts.resolve_incident(incident)
        Logger.info("monitor recovered", monitor_id: monitor.id, monitor_name: monitor.name)
        Monitoring.broadcast(monitor, {:incident_resolved, resolved})
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp apply_transition(_monitor, :no_change), do: :ok

  defp http_client,
    do: Pulsewatch.Config.impl(:http_client, Pulsewatch.Monitoring.HttpClient.ReqClient)

  defp tcp_client,
    do: Pulsewatch.Config.impl(:tcp_client, Pulsewatch.Monitoring.TcpClient.GenTcpClient)
end
