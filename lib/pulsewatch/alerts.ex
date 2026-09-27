defmodule Pulsewatch.Alerts do
  @moduledoc """
  Opens/resolves incidents together with queueing their alert — in the
  same database transaction, via `Oban.insert/3` composed onto an
  `Ecto.Multi`. An incident is never recorded without its alert job being
  queued, and a job is never queued for an incident that didn't actually
  get recorded (e.g. because it lost the race against the database's
  partial unique index for "one open incident per monitor").

  This is deliberately a separate context from `Monitoring`: `Monitoring`
  has no idea Oban exists, which keeps it simple to test and reusable if
  the alerting mechanism ever changes. This module is the seam that
  composes the two.
  """

  alias Pulsewatch.Alerts.IncidentAlertWorker
  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.{Incident, Monitor}
  alias Pulsewatch.Repo

  @doc "Opens an incident for `monitor` and atomically queues its alert job."
  @spec open_incident(Monitor.t(), DateTime.t()) ::
          {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
  def open_incident(%Monitor{} = monitor, started_at \\ DateTime.utc_now()) do
    monitor
    |> Monitoring.open_incident_multi(started_at)
    |> queue_alert("opened")
    |> Repo.transaction()
    |> unwrap()
  end

  @doc "Resolves `incident` and atomically queues its alert job."
  @spec resolve_incident(Incident.t(), DateTime.t(), String.t() | nil) ::
          {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
  def resolve_incident(
        %Incident{} = incident,
        resolved_at \\ DateTime.utc_now(),
        ai_summary \\ nil
      ) do
    incident
    |> Monitoring.resolve_incident_multi(resolved_at, ai_summary)
    |> queue_alert("resolved")
    |> Repo.transaction()
    |> unwrap()
  end

  # event is "opened" | "resolved" — a plain string, matching what it'll
  # be once it round-trips through the job's JSON-encoded args.
  defp queue_alert(multi, event) do
    Oban.insert(multi, :alert_job, fn %{incident: incident} ->
      IncidentAlertWorker.new(%{incident_id: incident.id, event: event})
    end)
  end

  defp unwrap({:ok, %{incident: incident}}), do: {:ok, incident}
  defp unwrap({:error, :incident, changeset, _changes_so_far}), do: {:error, changeset}
end
