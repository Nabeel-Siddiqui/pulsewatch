defmodule Pulsewatch.Alerts.IncidentAlertWorker do
  @moduledoc """
  Sends the "your monitor went down / recovered" notification: always an
  email, and a webhook POST too if the monitor has one configured.

  Email delivery is best-effort — a failure is logged, not retried. Retrying
  the whole job on an email failure would re-send the webhook too, and a
  webhook receiver isn't guaranteed to treat a redelivery as a no-op. The
  webhook POST is what actually gets Oban's retry-with-backoff treatment
  (`max_attempts: 5`), since that's the one specifically expected to be
  reliable.

  `unique` is keyed on `incident_id` + `event`, for the life of the job
  table (`period: :infinity`) — the same incident transition should never
  produce two alert jobs, however it got triggered.
  """

  use Oban.Worker,
    queue: :alerts,
    max_attempts: 5,
    unique: [fields: [:args], keys: [:incident_id, :event], period: :infinity]

  require Logger

  alias Pulsewatch.Alerts.IncidentMailer
  alias Pulsewatch.Monitoring

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"incident_id" => incident_id, "event" => event}})
      when event in ["opened", "resolved"] do
    incident = Monitoring.get_incident!(incident_id)
    monitor = incident.monitor

    deliver_email(monitor.user, monitor, incident, event)
    deliver_webhook(monitor, incident, event)
  end

  defp deliver_email(user, monitor, incident, event) do
    case IncidentMailer.deliver_incident_email(user, monitor, incident, event) do
      {:ok, _metadata} ->
        :ok

      {:error, reason} ->
        Logger.error("failed to send incident email",
          incident_id: incident.id,
          monitor_id: monitor.id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp deliver_webhook(%{webhook_url: nil}, _incident, _event), do: :ok

  defp deliver_webhook(monitor, incident, event) do
    payload = %{
      event: "incident_#{event}",
      monitor: %{id: monitor.id, name: monitor.name, url: monitor.url},
      incident: %{
        id: incident.id,
        started_at: incident.started_at,
        resolved_at: incident.resolved_at,
        ai_summary: incident.ai_summary
      }
    }

    case webhook_client().post(monitor.webhook_url, payload) do
      {:ok, _status} ->
        :ok

      {:error, reason} ->
        Logger.warning("webhook delivery failed, will retry",
          incident_id: incident.id,
          monitor_id: monitor.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp webhook_client do
    Application.get_env(:pulsewatch, :webhook_client, Pulsewatch.Alerts.WebhookClient.ReqClient)
  end
end
