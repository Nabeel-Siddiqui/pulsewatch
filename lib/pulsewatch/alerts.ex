defmodule Pulsewatch.Alerts do
  @moduledoc """
  Reacts to incidents opening and resolving: queues the notification
  (email + optional webhook) every time, and on resolution also queues
  the AI summary job — all in the same database transaction as the
  incident write itself, via `Oban.insert/3` composed onto an
  `Ecto.Multi`. An incident is never recorded without its jobs being
  queued, and no job is queued for an incident that didn't actually get
  recorded (e.g. because it lost the race against the database's partial
  unique index for "one open incident per monitor").

  This is deliberately a separate context from `Monitoring`: `Monitoring`
  has no idea Oban exists, which keeps it simple to test and reusable if
  the notification/summary mechanisms ever change. This module is the
  seam that composes them. It depends on `Pulsewatch.Ai` (to reference
  `IncidentSummaryWorker`) but not the other way around — `Ai` has no
  idea `Alerts` exists, so there's no risk of the two ending up in a
  circular dependency chain.
  """

  alias Pulsewatch.Ai.IncidentSummaryWorker
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

  @doc """
  Resolves `incident` and atomically queues both its alert job and its AI
  summary job.

  The alert job is scheduled a few seconds out, specifically for the
  "resolved" event — a short, best-effort head start for the summary job
  (enqueued in this same transaction) to finish first, so the resolve
  email usually includes the summary rather than always going out before
  one could possibly exist. This is a nudge, not a real dependency: the
  two jobs don't know about each other, neither blocks on the other, and
  if the LLM is slow or down the email still sends on time, just without
  a summary — consistent with the summary being optional everywhere else.
  A hard dependency (e.g. the summary job enqueueing the alert job itself)
  was the alternative, but that would make `Ai` depend on `Alerts` while
  `Alerts` already depends on `Ai`, a circular coupling not worth taking
  on for a "usually" instead of an "always."
  """
  @spec resolve_incident(Incident.t(), DateTime.t(), String.t() | nil) ::
          {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
  def resolve_incident(
        %Incident{} = incident,
        resolved_at \\ DateTime.utc_now(),
        ai_summary \\ nil
      ) do
    incident
    |> Monitoring.resolve_incident_multi(resolved_at, ai_summary)
    |> queue_alert("resolved", schedule_in: 5)
    |> queue_summary()
    |> Repo.transaction()
    |> unwrap()
  end

  # event is "opened" | "resolved" — a plain string, matching what it'll
  # be once it round-trips through the job's JSON-encoded args.
  defp queue_alert(multi, event, opts \\ []) do
    Oban.insert(multi, :alert_job, fn %{incident: incident} ->
      IncidentAlertWorker.new(%{incident_id: incident.id, event: event}, opts)
    end)
  end

  defp queue_summary(multi) do
    Oban.insert(multi, :summary_job, fn %{incident: incident} ->
      IncidentSummaryWorker.new(%{incident_id: incident.id})
    end)
  end

  defp unwrap({:ok, %{incident: incident}}), do: {:ok, incident}
  defp unwrap({:error, :incident, changeset, _changes_so_far}), do: {:error, changeset}
end
