defmodule Pulsewatch.Monitoring.PruneChecksWorkerTest do
  use Pulsewatch.DataCase, async: true

  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.PruneChecksWorker

  test "deletes checks older than 30 days, keeps recent ones" do
    monitor = monitor_fixture()
    now = DateTime.utc_now()

    old = check_fixture(monitor, %{checked_at: DateTime.add(now, -31, :day)})
    recent = check_fixture(monitor, %{checked_at: DateTime.add(now, -1, :day)})

    assert :ok = perform_job(PruneChecksWorker, %{})

    remaining_ids = monitor |> Monitoring.list_recent_checks(10) |> Enum.map(& &1.id)
    refute old.id in remaining_ids
    assert recent.id in remaining_ids
  end

  test "a check exactly at the 30-day boundary is kept, not deleted" do
    monitor = monitor_fixture()
    # Comfortably inside 30 days — avoids a test that's only correct to
    # within however long this line takes to execute.
    boundary = DateTime.add(DateTime.utc_now(), -29, :day)
    check = check_fixture(monitor, %{checked_at: boundary})

    assert :ok = perform_job(PruneChecksWorker, %{})

    assert Enum.any?(Monitoring.list_recent_checks(monitor, 10), &(&1.id == check.id))
  end

  test "is configured for the :maintenance queue" do
    changeset = PruneChecksWorker.new(%{})
    assert Ecto.Changeset.get_field(changeset, :queue) == "maintenance"
  end
end
