defmodule Pulsewatch.Alerts.IncidentAlertWorkerTest do
  use Pulsewatch.DataCase, async: true

  import Mox
  import Pulsewatch.AccountsFixtures
  import Pulsewatch.MonitoringFixtures
  import Swoosh.TestAssertions

  alias Pulsewatch.Alerts.IncidentAlertWorker
  alias Pulsewatch.Monitoring

  setup :verify_on_exit!

  defp job_for(incident, event) do
    %{incident_id: incident.id, event: event}
  end

  describe "perform/1 — email" do
    test "emails the monitor's owner when an incident opens" do
      user = user_fixture()
      monitor = monitor_fixture(%{user: user})
      {:ok, incident} = Monitoring.open_incident(monitor)

      assert :ok = perform_job(IncidentAlertWorker, job_for(incident, "opened"))

      assert_email_sent(to: user.email, subject: "🔴 #{monitor.name} is down")
    end

    test "emails the monitor's owner when an incident resolves" do
      user = user_fixture()
      monitor = monitor_fixture(%{user: user})
      {:ok, incident} = Monitoring.open_incident(monitor)
      {:ok, resolved} = Monitoring.resolve_incident(incident)

      assert :ok = perform_job(IncidentAlertWorker, job_for(resolved, "resolved"))

      assert_email_sent(to: user.email, subject: "✅ #{monitor.name} recovered")
    end
  end

  describe "perform/1 — webhook" do
    test "posts to the monitor's webhook_url when one is configured" do
      monitor = monitor_fixture(%{webhook_url: "https://hooks.example.com/alert"})
      {:ok, incident} = Monitoring.open_incident(monitor)

      expect(Pulsewatch.Alerts.WebhookClientMock, :post, fn url, payload ->
        assert url == "https://hooks.example.com/alert"
        assert payload.event == "incident_opened"
        assert payload.monitor.id == monitor.id
        {:ok, 200}
      end)

      assert :ok = perform_job(IncidentAlertWorker, job_for(incident, "opened"))
    end

    test "skips the webhook entirely when the monitor has none configured" do
      monitor = monitor_fixture(%{webhook_url: nil})
      {:ok, incident} = Monitoring.open_incident(monitor)

      # No Mox expectation set at all — if the worker tried to call the
      # webhook client anyway, this test would fail with an unexpected call.
      assert :ok = perform_job(IncidentAlertWorker, job_for(incident, "opened"))
    end

    test "a webhook failure returns {:error, _} so Oban retries with backoff" do
      monitor = monitor_fixture(%{webhook_url: "https://hooks.example.com/alert"})
      {:ok, incident} = Monitoring.open_incident(monitor)

      expect(Pulsewatch.Alerts.WebhookClientMock, :post, fn _url, _payload ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = perform_job(IncidentAlertWorker, job_for(incident, "opened"))
    end
  end

  test "the job is configured for 5 attempts in the :alerts queue" do
    changeset = IncidentAlertWorker.new(%{incident_id: 1, event: "opened"})

    assert Ecto.Changeset.get_field(changeset, :max_attempts) == 5
    assert Ecto.Changeset.get_field(changeset, :queue) == "alerts"
  end
end
