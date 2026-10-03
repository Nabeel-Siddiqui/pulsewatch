defmodule Pulsewatch.Ai.IncidentSummaryWorker do
  @moduledoc """
  Generates and saves a short AI summary of a resolved incident's check
  history. Entirely best-effort: whether the LLM call succeeds or fails,
  this job always finishes with `:ok` — a summary is a nice-to-have on
  the incident history page and in the resolve email, never something
  the rest of the app waits on or fails over. If it fails, the incident
  simply has no summary; nothing about incident resolution or alerting
  depends on this job succeeding.

  `unique` on `incident_id` alone (not `event`, unlike the alert worker —
  there's only one kind of event here) for the life of the job table, so
  a given incident is never summarized twice. `:worker` has to stay in
  `fields` alongside `:args` — see the identical note on
  `Alerts.IncidentAlertWorker`, whose job this one was silently matching
  as a "duplicate" of before that fix, since both jobs carry an
  `incident_id` and dropping `:worker` from the comparison makes Oban's
  uniqueness check worker-agnostic.
  """

  use Oban.Worker,
    queue: :ai,
    max_attempts: 3,
    unique: [fields: [:args, :worker], keys: [:incident_id], period: :infinity]

  require Logger

  alias Pulsewatch.Ai.PromptBuilder
  alias Pulsewatch.Monitoring

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"incident_id" => incident_id}}) do
    incident = Monitoring.get_incident!(incident_id)
    monitor = incident.monitor
    checks = Monitoring.list_checks_during(monitor, incident.started_at, incident.resolved_at)
    prompt = PromptBuilder.build(monitor, incident, checks)

    case call_llm(prompt, incident.id) do
      {:ok, summary} ->
        {:ok, updated} = Monitoring.update_incident_summary(incident, summary)
        # Re-broadcast :incident_resolved with the now-summarized incident
        # so the detail page picks up the summary live, without a reload
        # — the original resolve broadcast fired before this job even
        # started, so it never had a summary to include.
        Monitoring.broadcast(monitor, {:incident_resolved, updated})
        :ok

      {:error, reason} ->
        Logger.warning("incident summary generation failed, leaving it unsummarized",
          incident_id: incident.id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  # Wrapped in a span (not just the raw client call) so LiveDashboard sees
  # LLM latency/result regardless of which client implementation is
  # configured — Anthropic, the demo client, or (in tests) the Mox mock.
  defp call_llm(prompt, incident_id) do
    :telemetry.span([:pulsewatch, :llm], %{incident_id: incident_id}, fn ->
      result = llm_client().complete(prompt)
      status = if match?({:ok, _}, result), do: :ok, else: :error
      {result, %{incident_id: incident_id, result: status}}
    end)
  end

  defp llm_client,
    do: Pulsewatch.Config.impl(:llm_client, Pulsewatch.Ai.LlmClient.AnthropicClient)
end
