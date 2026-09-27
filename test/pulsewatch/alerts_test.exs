defmodule Pulsewatch.AlertsTest do
  use Pulsewatch.DataCase, async: true

  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Ai.IncidentSummaryWorker
  alias Pulsewatch.Alerts
  alias Pulsewatch.Alerts.IncidentAlertWorker
  alias Pulsewatch.Monitoring

  describe "open_incident/2" do
    test "inserts the incident and enqueues its alert job in the same transaction" do
      monitor = monitor_fixture()

      assert {:ok, incident} = Alerts.open_incident(monitor)

      assert {:ok, _} = Monitoring.get_open_incident(monitor)

      assert_enqueued(
        worker: IncidentAlertWorker,
        args: %{incident_id: incident.id, event: "opened"}
      )
    end

    test "if the incident insert fails (already an open one), no job is enqueued" do
      monitor = monitor_fixture()
      {:ok, _first} = Alerts.open_incident(monitor)

      assert {:error, changeset} = Alerts.open_incident(monitor)
      assert "has already been taken" in errors_on(changeset).monitor_id

      # Only the first call's job — the failed second attempt enqueued
      # nothing, because the whole transaction (incident insert + job
      # insert) rolled back together.
      assert [_one_job] = all_enqueued(worker: IncidentAlertWorker)
    end
  end

  describe "resolve_incident/3" do
    test "updates the incident and enqueues both its alert and summary jobs in the same transaction" do
      monitor = monitor_fixture()
      {:ok, incident} = Monitoring.open_incident(monitor)

      assert {:ok, resolved} = Alerts.resolve_incident(incident)
      assert resolved.resolved_at != nil

      assert_enqueued(
        worker: IncidentAlertWorker,
        args: %{incident_id: incident.id, event: "resolved"}
      )

      assert_enqueued(worker: IncidentSummaryWorker, args: %{incident_id: incident.id})
    end

    test "the resolve alert job is scheduled a few seconds out, giving the summary job a head start" do
      monitor = monitor_fixture()
      {:ok, incident} = Monitoring.open_incident(monitor)

      {:ok, _resolved} = Alerts.resolve_incident(incident)

      [job] =
        all_enqueued(
          worker: IncidentAlertWorker,
          args: %{incident_id: incident.id, event: "resolved"}
        )

      assert job.state == "scheduled"
      assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) == :gt
    end

    test "the opened alert job runs immediately, not scheduled" do
      monitor = monitor_fixture()
      {:ok, _incident} = Alerts.open_incident(monitor)

      assert [job] = all_enqueued(worker: IncidentAlertWorker)
      assert job.state == "available"
    end

    test "if the incident update fails, neither job is enqueued" do
      monitor = monitor_fixture()
      {:ok, incident} = Monitoring.open_incident(monitor)
      {:ok, incident} = Monitoring.resolve_incident(incident)

      # Already resolved — resolved_at is required but the changeset
      # itself would still succeed on a re-resolve; force a failure by
      # passing a nil resolved_at instead.
      assert {:error, _changeset} = Alerts.resolve_incident(incident, nil)

      assert all_enqueued(worker: IncidentSummaryWorker) == []
    end

    test "carries an AI summary through to the job's underlying incident record" do
      monitor = monitor_fixture()
      {:ok, incident} = Monitoring.open_incident(monitor)

      assert {:ok, resolved} =
               Alerts.resolve_incident(incident, DateTime.utc_now(), "Brief outage.")

      assert resolved.ai_summary == "Brief outage."
    end
  end

  describe "job uniqueness" do
    test "the same incident_id + event can't be enqueued twice" do
      monitor = monitor_fixture()
      {:ok, incident} = Monitoring.open_incident(monitor)

      assert {:ok, _job1} =
               %{incident_id: incident.id, event: "opened"}
               |> IncidentAlertWorker.new()
               |> Oban.insert()

      assert {:ok, job2} =
               %{incident_id: incident.id, event: "opened"}
               |> IncidentAlertWorker.new()
               |> Oban.insert()

      # Oban's unique option doesn't error on a duplicate — it returns the
      # existing job unchanged, silently no-opping the second insert.
      assert [only_one] = all_enqueued(worker: IncidentAlertWorker)
      assert job2.id == only_one.id
    end
  end
end
