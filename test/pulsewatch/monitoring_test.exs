defmodule Pulsewatch.MonitoringTest do
  use Pulsewatch.DataCase

  import Pulsewatch.AccountsFixtures
  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.{Check, Incident, Monitor}

  describe "monitors" do
    @valid_attrs %{
      name: "Example",
      url: "https://example.com",
      check_interval_seconds: 60,
      expected_status_code: 200,
      timeout_ms: 5_000
    }

    test "list_monitors/1 returns only the given user's monitors" do
      user = user_fixture()
      other_user = user_fixture()
      mine = monitor_fixture(%{user: user})
      _theirs = monitor_fixture(%{user: other_user})

      assert Monitoring.list_monitors(user) == [mine]
    end

    test "get_monitor/2 returns {:error, :not_found} for another user's monitor" do
      owner = user_fixture()
      stranger = user_fixture()
      monitor = monitor_fixture(%{user: owner})

      assert {:ok, ^monitor} = Monitoring.get_monitor(owner, monitor.id)
      assert {:error, :not_found} = Monitoring.get_monitor(stranger, monitor.id)
    end

    test "get_monitor!/2 raises for another user's monitor" do
      owner = user_fixture()
      stranger = user_fixture()
      monitor = monitor_fixture(%{user: owner})

      assert Monitoring.get_monitor!(owner, monitor.id) == monitor
      assert_raise Ecto.NoResultsError, fn -> Monitoring.get_monitor!(stranger, monitor.id) end
    end

    test "create_monitor/2 with valid data creates a monitor owned by the user" do
      user = user_fixture()

      assert {:ok, %Monitor{} = monitor} = Monitoring.create_monitor(user, @valid_attrs)
      assert monitor.user_id == user.id
      assert monitor.name == "Example"
      assert monitor.active == true
    end

    test "create_monitor/2 rejects a non-http(s) or hostless url" do
      user = user_fixture()

      for bad_url <- ["not a url", "ftp://example.com", "https://", "javascript:alert(1)"] do
        assert {:error, changeset} =
                 Monitoring.create_monitor(user, %{@valid_attrs | url: bad_url})

        assert "must be a valid http or https URL" in errors_on(changeset).url
      end
    end

    test "create_monitor/2 rejects a check_interval_seconds outside 30..3600" do
      user = user_fixture()

      assert {:error, changeset} =
               Monitoring.create_monitor(user, %{@valid_attrs | check_interval_seconds: 10})

      assert %{check_interval_seconds: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Monitoring.create_monitor(user, %{@valid_attrs | check_interval_seconds: 9999})

      assert %{check_interval_seconds: [_]} = errors_on(changeset)
    end

    test "create_monitor/2 accepts a blank webhook_url but rejects a malformed one" do
      user = user_fixture()

      assert {:ok, _} = Monitoring.create_monitor(user, Map.put(@valid_attrs, :webhook_url, ""))

      assert {:error, changeset} =
               Monitoring.create_monitor(user, Map.put(@valid_attrs, :webhook_url, "nope"))

      assert "must be a valid http or https URL" in errors_on(changeset).webhook_url
    end

    test "update_monitor/3 updates when the user owns the monitor" do
      user = user_fixture()
      monitor = monitor_fixture(%{user: user})

      assert {:ok, %Monitor{name: "New name"}} =
               Monitoring.update_monitor(user, monitor, %{name: "New name"})
    end

    test "update_monitor/3 returns {:error, :not_found} when the user doesn't own the monitor" do
      owner = user_fixture()
      stranger = user_fixture()
      monitor = monitor_fixture(%{user: owner})

      assert {:error, :not_found} =
               Monitoring.update_monitor(stranger, monitor, %{name: "Hijacked"})

      assert Monitoring.get_monitor!(owner, monitor.id).name == monitor.name
    end

    test "delete_monitor/2 deletes when the user owns the monitor" do
      user = user_fixture()
      monitor = monitor_fixture(%{user: user})

      assert {:ok, %Monitor{}} = Monitoring.delete_monitor(user, monitor)
      assert {:error, :not_found} = Monitoring.get_monitor(user, monitor.id)
    end

    test "delete_monitor/2 returns {:error, :not_found} when the user doesn't own the monitor" do
      owner = user_fixture()
      stranger = user_fixture()
      monitor = monitor_fixture(%{user: owner})

      assert {:error, :not_found} = Monitoring.delete_monitor(stranger, monitor)
      assert {:ok, _} = Monitoring.get_monitor(owner, monitor.id)
    end

    test "pause_monitor/2 and resume_monitor/2 toggle :active" do
      user = user_fixture()
      monitor = monitor_fixture(%{user: user})

      assert {:ok, %Monitor{active: false} = paused} = Monitoring.pause_monitor(user, monitor)
      assert {:ok, %Monitor{active: true}} = Monitoring.resume_monitor(user, paused)
    end

    test "change_monitor/2 returns a changeset without touching the database" do
      monitor = monitor_fixture()
      assert %Ecto.Changeset{} = Monitoring.change_monitor(monitor)
    end
  end

  describe "checks" do
    test "create_check/2 records a check against a monitor" do
      monitor = monitor_fixture()

      assert {:ok, %Check{} = check} =
               Monitoring.create_check(monitor, %{
                 status: :up,
                 status_code: 200,
                 response_time_ms: 88,
                 checked_at: DateTime.utc_now()
               })

      assert check.monitor_id == monitor.id
      assert check.status == :up
    end

    test "create_check/2 allows a :down check with no status_code (e.g. connection timeout)" do
      monitor = monitor_fixture()

      assert {:ok, %Check{status: :down}} =
               Monitoring.create_check(monitor, %{
                 status: :down,
                 error_message: "timeout",
                 checked_at: DateTime.utc_now()
               })
    end

    test "list_recent_checks/2 returns newest first, respecting the limit" do
      monitor = monitor_fixture()
      base = DateTime.utc_now()

      for i <- 1..5 do
        check_fixture(monitor, %{checked_at: DateTime.add(base, i, :second)})
      end

      [newest, next | _] = Monitoring.list_recent_checks(monitor, 2)
      assert DateTime.compare(newest.checked_at, next.checked_at) == :gt
      assert length(Monitoring.list_recent_checks(monitor, 2)) == 2
    end
  end

  describe "incidents" do
    test "open_incident/2 then get_open_incident/1 round-trips" do
      monitor = monitor_fixture()
      assert {:error, :not_found} = Monitoring.get_open_incident(monitor)

      assert {:ok, %Incident{resolved_at: nil}} = Monitoring.open_incident(monitor)
      assert {:ok, %Incident{}} = Monitoring.get_open_incident(monitor)
    end

    test "a monitor can only have one open incident at a time" do
      monitor = monitor_fixture()
      assert {:ok, _} = Monitoring.open_incident(monitor)

      assert {:error, changeset} = Monitoring.open_incident(monitor)
      assert "has already been taken" in errors_on(changeset).monitor_id
    end

    test "resolving an incident clears the open-incident lookup, allowing a new one" do
      monitor = monitor_fixture()
      {:ok, incident} = Monitoring.open_incident(monitor)

      assert {:ok, %Incident{resolved_at: %DateTime{}}} = Monitoring.resolve_incident(incident)
      assert {:error, :not_found} = Monitoring.get_open_incident(monitor)
      assert {:ok, _} = Monitoring.open_incident(monitor)
    end

    test "resolve_incident/3 accepts an optional AI summary" do
      monitor = monitor_fixture()
      {:ok, incident} = Monitoring.open_incident(monitor)

      assert {:ok, %Incident{ai_summary: "Brief outage."}} =
               Monitoring.resolve_incident(incident, DateTime.utc_now(), "Brief outage.")
    end

    test "list_incidents/1 returns a monitor's incidents, most recent first" do
      monitor = monitor_fixture()
      older = incident_fixture(monitor, DateTime.add(DateTime.utc_now(), -3600, :second))
      {:ok, _} = Monitoring.resolve_incident(older)
      newer = incident_fixture(monitor)

      assert Monitoring.list_incidents(monitor) |> Enum.map(& &1.id) == [newer.id, older.id]
    end
  end
end
