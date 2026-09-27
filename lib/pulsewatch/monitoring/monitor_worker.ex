defmodule Pulsewatch.Monitoring.MonitorWorker do
  @moduledoc """
  One process per actively-checked monitor. Schedules itself with
  `Process.send_after/3` plus random jitter (so N workers started at the
  same moment — e.g. at application boot — don't all hit the network in
  the same instant), and hands off the actual check to
  `Pulsewatch.Monitoring.Checker`.

  Registered in `Pulsewatch.Monitoring.Registry` under the monitor's id,
  so there's at most one worker per monitor and it can be found/stopped
  by id without tracking pids anywhere else.
  """

  use GenServer, restart: :transient

  alias Pulsewatch.Monitoring.{Checker, Monitor}

  # Spread the first check, and every subsequent one, across up to 5s so
  # a fleet of workers scheduled together doesn't check in lockstep.
  @jitter_ms 5_000

  @type state :: %{monitor: Monitor.t(), consecutive_failures: non_neg_integer()}

  @spec start_link(Monitor.t()) :: GenServer.on_start()
  def start_link(monitor) do
    GenServer.start_link(__MODULE__, monitor, name: via(monitor.id))
  end

  @doc "The `:via` tuple for the worker registered under `monitor_id`, for Registry/DynamicSupervisor lookups."
  @spec via(term()) :: {:via, Registry, {module(), term()}}
  def via(monitor_id) do
    {:via, Registry, {Pulsewatch.Monitoring.Registry, monitor_id}}
  end

  @impl true
  def init(monitor) do
    schedule_check(0)
    {:ok, %{monitor: monitor, consecutive_failures: 0}}
  end

  @impl true
  def handle_info(:check, state) do
    Logger.metadata(monitor_id: state.monitor.id)

    %{consecutive_failures: new_failures} = Checker.run(state.monitor, state.consecutive_failures)

    schedule_check(state.monitor.check_interval_seconds * 1_000)
    {:noreply, %{state | consecutive_failures: new_failures}}
  end

  defp schedule_check(base_delay_ms) do
    Process.send_after(self(), :check, base_delay_ms + :rand.uniform(@jitter_ms))
  end
end
