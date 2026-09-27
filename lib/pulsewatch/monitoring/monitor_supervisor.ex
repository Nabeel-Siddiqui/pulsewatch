defmodule Pulsewatch.Monitoring.MonitorSupervisor do
  @moduledoc """
  Dynamically starts and stops one `MonitorWorker` per active monitor.

  Uses the default `:one_for_one` strategy, so a crash in one worker only
  restarts that worker — its siblings are untouched. Workers are looked
  up by monitor id through `Pulsewatch.Monitoring.Registry` rather than
  by tracking pids anywhere, so start/stop/restart are idempotent and
  don't require the caller to have a pid on hand.
  """

  use DynamicSupervisor

  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.{Monitor, MonitorWorker}

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Starts a worker for `monitor`, unless one is already running."
  @spec start_worker(Monitor.t()) :: :ok
  def start_worker(%Monitor{} = monitor) do
    case DynamicSupervisor.start_child(__MODULE__, {MonitorWorker, monitor}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @doc "Stops the running worker for `monitor_id`, if any."
  @spec stop_worker(term()) :: :ok
  def stop_worker(monitor_id) do
    case Registry.lookup(Pulsewatch.Monitoring.Registry, monitor_id) do
      [{pid, _value}] -> :ok = supervisor_terminate(pid)
      [] -> :ok
    end
  end

  @doc """
  Restarts the worker for `monitor` so it picks up changed config (url,
  interval, timeout, ...). A no-op followed by a start if none was running.
  """
  @spec restart_worker(Monitor.t()) :: :ok
  def restart_worker(%Monitor{} = monitor) do
    stop_worker(monitor.id)
    start_worker(monitor)
  end

  @doc "Starts a worker for every currently-active monitor. Called once at application boot."
  @spec start_all_active_monitors() :: :ok
  def start_all_active_monitors do
    Monitoring.list_active_monitors()
    |> Enum.each(&start_worker/1)
  end

  @doc "The number of monitor workers currently running. Used by the /health endpoint."
  @spec worker_count() :: non_neg_integer()
  def worker_count do
    %{active: count} = DynamicSupervisor.count_children(__MODULE__)
    count
  end

  defp supervisor_terminate(pid) do
    case DynamicSupervisor.terminate_child(__MODULE__, pid) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end
end
