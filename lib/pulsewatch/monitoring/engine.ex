defmodule Pulsewatch.Monitoring.Engine do
  @moduledoc """
  Keeps `MonitorWorker` processes in sync with `Monitor` records.

  `Pulsewatch.Monitoring` is a plain data layer — it has no idea a
  checking engine exists, which keeps it simple to test on its own. This
  module is the thin seam above it: every write that should affect a
  running worker (create, update, pause, resume, delete) goes through
  here instead, so the OTP process tree and the database never drift
  apart. Callers that only read data (list/get) go straight to
  `Pulsewatch.Monitoring` — there's nothing to sync.
  """

  alias Pulsewatch.Accounts.User
  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.{Monitor, MonitorSupervisor}

  @doc "Creates a monitor and starts its worker if it's active."
  @spec create_monitor(User.t(), map()) :: {:ok, Monitor.t()} | {:error, Ecto.Changeset.t()}
  def create_monitor(%User{} = user, attrs) do
    with {:ok, monitor} <- Monitoring.create_monitor(user, attrs) do
      if monitor.active, do: MonitorSupervisor.start_worker(monitor)
      {:ok, monitor}
    end
  end

  @doc """
  Updates a monitor and resyncs its worker: restarted if still active (so
  a changed url/interval/timeout takes effect immediately), stopped if the
  update turned it inactive.
  """
  @spec update_monitor(User.t(), Monitor.t(), map()) ::
          {:ok, Monitor.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_monitor(%User{} = user, %Monitor{} = monitor, attrs) do
    with {:ok, updated} <- Monitoring.update_monitor(user, monitor, attrs) do
      sync_worker(updated)
      {:ok, updated}
    end
  end

  @doc "Pauses a monitor and stops its worker."
  @spec pause_monitor(User.t(), Monitor.t()) ::
          {:ok, Monitor.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def pause_monitor(%User{} = user, %Monitor{} = monitor) do
    with {:ok, updated} <- Monitoring.pause_monitor(user, monitor) do
      :ok = MonitorSupervisor.stop_worker(updated.id)
      {:ok, updated}
    end
  end

  @doc "Resumes a paused monitor and starts its worker."
  @spec resume_monitor(User.t(), Monitor.t()) ::
          {:ok, Monitor.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def resume_monitor(%User{} = user, %Monitor{} = monitor) do
    with {:ok, updated} <- Monitoring.resume_monitor(user, monitor) do
      :ok = MonitorSupervisor.start_worker(updated)
      {:ok, updated}
    end
  end

  @doc "Deletes a monitor and stops its worker."
  @spec delete_monitor(User.t(), Monitor.t()) ::
          {:ok, Monitor.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def delete_monitor(%User{} = user, %Monitor{} = monitor) do
    with {:ok, deleted} <- Monitoring.delete_monitor(user, monitor) do
      :ok = MonitorSupervisor.stop_worker(deleted.id)
      {:ok, deleted}
    end
  end

  defp sync_worker(%Monitor{active: true} = monitor),
    do: MonitorSupervisor.restart_worker(monitor)

  defp sync_worker(%Monitor{active: false} = monitor),
    do: MonitorSupervisor.stop_worker(monitor.id)
end
