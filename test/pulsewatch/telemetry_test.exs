defmodule Pulsewatch.TelemetryTest do
  use Pulsewatch.DataCase, async: true

  import Mox
  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Ai.IncidentSummaryWorker
  alias Pulsewatch.Alerts.IncidentAlertWorker
  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.Checker

  setup :verify_on_exit!

  # `:telemetry.attach/4` registers a handler for *every* emission of an
  # event VM-wide — it is not scoped to the attaching process. Under
  # `async: true`, other tests (in this file and others, e.g. CheckerTest,
  # MonitorWorkerTest) are concurrently emitting these same events for
  # their own monitors/incidents. A handler that just forwards every
  # occurrence will intermittently forward *someone else's* event to this
  # test first — confirmed by an actual flaky failure (a monitor_id
  # mismatch) before this filter was added, not a hypothetical concern.
  # Filtering by the specific id this test cares about, in the handler
  # itself, is what makes it safe to run concurrently with everything
  # else emitting the same event name.
  defp attach(event, match_key, match_value) do
    ref = make_ref()
    test_pid = self()
    handler_id = {event, ref}

    :telemetry.attach(
      handler_id,
      event,
      fn ^event, measurements, metadata, _config ->
        if Map.get(metadata, match_key) == match_value do
          send(test_pid, {:telemetry_event, ref, measurements, metadata})
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    ref
  end

  test "a monitor check emits [:pulsewatch, :monitor, :check, :stop] with duration and status" do
    monitor = monitor_fixture()
    ref = attach([:pulsewatch, :monitor, :check, :stop], :monitor_id, monitor.id)
    expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:ok, 200} end)

    Checker.run(monitor, 0)

    assert_receive {:telemetry_event, ^ref, measurements, metadata}
    assert is_integer(measurements.duration)
    assert measurements.duration > 0
    assert metadata.status == :up
    assert metadata.monitor_id == monitor.id
  end

  test "a failing check tags the event with status: :down" do
    monitor = monitor_fixture()
    ref = attach([:pulsewatch, :monitor, :check, :stop], :monitor_id, monitor.id)

    expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:error, :timeout} end)

    Checker.run(monitor, 0)

    assert_receive {:telemetry_event, ^ref, _measurements, %{status: :down}}
  end

  test "delivering an alert emits [:pulsewatch, :alert, :sent] per channel" do
    monitor = monitor_fixture(%{webhook_url: "https://hooks.example.com/alert"})
    {:ok, incident} = Monitoring.open_incident(monitor)
    ref = attach([:pulsewatch, :alert, :sent], :incident_id, incident.id)

    expect(Pulsewatch.Alerts.WebhookClientMock, :post, fn _url, _payload -> {:ok, 200} end)

    assert :ok =
             perform_job(IncidentAlertWorker, %{incident_id: incident.id, event: "opened"})

    assert_receive {:telemetry_event, ^ref, %{count: 1}, %{channel: :email, result: :ok}}
    assert_receive {:telemetry_event, ^ref, %{count: 1}, %{channel: :webhook, result: :ok}}
  end

  test "a failed webhook is tagged result: :error in its telemetry event" do
    monitor = monitor_fixture(%{webhook_url: "https://hooks.example.com/alert"})
    {:ok, incident} = Monitoring.open_incident(monitor)
    ref = attach([:pulsewatch, :alert, :sent], :incident_id, incident.id)

    expect(Pulsewatch.Alerts.WebhookClientMock, :post, fn _url, _payload -> {:error, :timeout} end)

    perform_job(IncidentAlertWorker, %{incident_id: incident.id, event: "opened"})

    assert_receive {:telemetry_event, ^ref, _, %{channel: :webhook, result: :error}}
  end

  test "generating an incident summary emits [:pulsewatch, :llm, :stop] with duration and result" do
    monitor = monitor_fixture()
    {:ok, incident} = Monitoring.open_incident(monitor)
    {:ok, incident} = Monitoring.resolve_incident(incident)
    ref = attach([:pulsewatch, :llm, :stop], :incident_id, incident.id)

    expect(Pulsewatch.Ai.LlmClientMock, :complete, fn _prompt -> {:ok, "summary"} end)

    assert :ok = perform_job(IncidentSummaryWorker, %{incident_id: incident.id})

    assert_receive {:telemetry_event, ^ref, measurements, metadata}
    assert is_integer(measurements.duration)
    assert metadata.result == :ok
    assert metadata.incident_id == incident.id
  end

  test "an LLM failure is tagged result: :error in its telemetry event" do
    monitor = monitor_fixture()
    {:ok, incident} = Monitoring.open_incident(monitor)
    {:ok, incident} = Monitoring.resolve_incident(incident)
    ref = attach([:pulsewatch, :llm, :stop], :incident_id, incident.id)

    expect(Pulsewatch.Ai.LlmClientMock, :complete, fn _prompt -> {:error, :timeout} end)

    perform_job(IncidentSummaryWorker, %{incident_id: incident.id})

    assert_receive {:telemetry_event, ^ref, _measurements, %{result: :error}}
  end
end
