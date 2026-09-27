defmodule Pulsewatch.Ai.IncidentSummaryWorkerTest do
  use Pulsewatch.DataCase, async: true

  import Mox
  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Ai.IncidentSummaryWorker
  alias Pulsewatch.Monitoring

  setup :verify_on_exit!

  test "saves the LLM's response as the incident's ai_summary" do
    monitor = monitor_fixture()
    {:ok, incident} = Monitoring.open_incident(monitor)
    {:ok, incident} = Monitoring.resolve_incident(incident)

    expect(Pulsewatch.Ai.LlmClientMock, :complete, fn prompt ->
      assert prompt =~ monitor.name
      {:ok, "The site was briefly unreachable and recovered on its own."}
    end)

    assert :ok = perform_job(IncidentSummaryWorker, %{incident_id: incident.id})

    updated = Monitoring.get_incident!(incident.id)
    assert updated.ai_summary == "The site was briefly unreachable and recovered on its own."
  end

  test "an LLM failure leaves the incident resolved but unsummarized — never blocks or errors the job" do
    monitor = monitor_fixture()
    {:ok, incident} = Monitoring.open_incident(monitor)
    {:ok, incident} = Monitoring.resolve_incident(incident)

    expect(Pulsewatch.Ai.LlmClientMock, :complete, fn _prompt -> {:error, :timeout} end)

    # :ok, not {:error, _} — a failed summary must never cause Oban to
    # retry-storm this job or look like a real failure anywhere upstream.
    assert :ok = perform_job(IncidentSummaryWorker, %{incident_id: incident.id})

    updated = Monitoring.get_incident!(incident.id)
    assert updated.ai_summary == nil
    assert updated.resolved_at != nil
  end

  test "includes only checks recorded during the incident's window" do
    monitor = monitor_fixture()
    {:ok, incident} = Monitoring.open_incident(monitor)

    before_check =
      check_fixture(monitor, %{
        status: :up,
        checked_at: DateTime.add(incident.started_at, -60, :second)
      })

    # Genuinely between started_at and resolved_at — taken from real
    # elapsed wall-clock time (each step is a DB round-trip), not an
    # artificial offset. A fixed "+5 seconds" would land after
    # resolved_at in a fast-running test, since open -> resolve here
    # takes milliseconds, not 5 real seconds.
    during_check = check_fixture(monitor, %{status: :down, checked_at: DateTime.utc_now()})

    {:ok, incident} = Monitoring.resolve_incident(incident)

    after_check =
      check_fixture(monitor, %{
        status: :up,
        checked_at: DateTime.add(incident.resolved_at, 60, :second)
      })

    expect(Pulsewatch.Ai.LlmClientMock, :complete, fn prompt ->
      refute prompt =~ inspect(before_check.id)
      refute prompt =~ inspect(after_check.id)
      assert prompt =~ Calendar.strftime(during_check.checked_at, "%H:%M:%S")
      {:ok, "summary"}
    end)

    assert :ok = perform_job(IncidentSummaryWorker, %{incident_id: incident.id})
  end

  test "is configured for the :ai queue with 3 attempts" do
    changeset = IncidentSummaryWorker.new(%{incident_id: 1})
    assert Ecto.Changeset.get_field(changeset, :queue) == "ai"
    assert Ecto.Changeset.get_field(changeset, :max_attempts) == 3
  end
end
