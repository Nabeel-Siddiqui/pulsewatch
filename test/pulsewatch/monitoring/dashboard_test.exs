defmodule Pulsewatch.Monitoring.DashboardTest do
  use Pulsewatch.DataCase, async: true

  import Pulsewatch.AccountsFixtures
  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Monitoring

  describe "dashboard_rows/1" do
    test "only includes the given user's monitors" do
      user = user_fixture()
      other_user = user_fixture()
      mine = monitor_fixture(%{user: user})
      _theirs = monitor_fixture(%{user: other_user})

      assert [%{monitor: %{id: id}}] = Monitoring.dashboard_rows(user)
      assert id == mine.id
    end

    test "a monitor with no checks yet has nil status/response time/uptime" do
      user = user_fixture()
      monitor_fixture(%{user: user})

      assert [row] = Monitoring.dashboard_rows(user)
      assert row.status == nil
      assert row.last_response_time_ms == nil
      assert row.last_checked_at == nil
      assert row.uptime_pct == nil
    end

    test "status/response time reflect the most recent check" do
      user = user_fixture()
      monitor = monitor_fixture(%{user: user})
      now = DateTime.utc_now()

      check_fixture(monitor, %{
        status: :up,
        response_time_ms: 100,
        checked_at: DateTime.add(now, -60, :second)
      })

      check_fixture(monitor, %{status: :down, response_time_ms: 999, checked_at: now})

      assert [row] = Monitoring.dashboard_rows(user)
      assert row.status == :down
      assert row.last_response_time_ms == 999
    end

    test "uptime_pct is the percentage of :up checks in the last 24h" do
      user = user_fixture()
      monitor = monitor_fixture(%{user: user})
      now = DateTime.utc_now()

      for _ <- 1..3, do: check_fixture(monitor, %{status: :up, checked_at: now})
      check_fixture(monitor, %{status: :down, error_message: "boom", checked_at: now})

      assert [row] = Monitoring.dashboard_rows(user)
      assert row.uptime_pct == 75.0
    end

    test "checks older than 24h don't count toward uptime_pct, but still count as the latest status if nothing newer exists" do
      user = user_fixture()
      monitor = monitor_fixture(%{user: user})
      two_days_ago = DateTime.add(DateTime.utc_now(), -48, :hour)

      check_fixture(monitor, %{status: :up, checked_at: two_days_ago})

      assert [row] = Monitoring.dashboard_rows(user)
      assert row.status == :up
      assert row.uptime_pct == nil
    end

    test "rows are ordered alphabetically by monitor name" do
      user = user_fixture()
      monitor_fixture(%{user: user, name: "Zebra"})
      monitor_fixture(%{user: user, name: "Alpha"})

      assert [%{monitor: %{name: "Alpha"}}, %{monitor: %{name: "Zebra"}}] =
               Monitoring.dashboard_rows(user)
    end
  end

  describe "list_checks_since/2" do
    test "returns only checks within the window, oldest first" do
      monitor = monitor_fixture()
      now = DateTime.utc_now()

      old = check_fixture(monitor, %{checked_at: DateTime.add(now, -48, :hour)})
      mid = check_fixture(monitor, %{checked_at: DateTime.add(now, -1, :hour)})
      recent = check_fixture(monitor, %{checked_at: now})

      result = Monitoring.list_checks_since(monitor, 24)

      assert Enum.map(result, & &1.id) == [mid.id, recent.id]
      refute Enum.any?(result, &(&1.id == old.id))
    end
  end
end
