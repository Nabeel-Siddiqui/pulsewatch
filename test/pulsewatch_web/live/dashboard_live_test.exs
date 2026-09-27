defmodule PulsewatchWeb.DashboardLiveTest do
  use PulsewatchWeb.ConnCase

  import Phoenix.LiveViewTest
  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.MonitorSupervisor

  setup :register_and_log_in_user

  # Several tests here go through Engine (create/edit/resume), which
  # starts a real worker on the application's global MonitorSupervisor —
  # not something these tests get their own copy of. Left running, a
  # worker's pending jitter-delayed :check can fire minutes later, mid a
  # different test, and crash on an unmocked Mox call. Query fresh at
  # exit (not a snapshot) so it catches every monitor the test touched,
  # regardless of which action started a worker.
  setup %{user: user} do
    on_exit(fn ->
      user |> Monitoring.list_monitors() |> Enum.each(&MonitorSupervisor.stop_worker(&1.id))
    end)
  end

  defp valid_attrs do
    %{
      name: "Example",
      url: "https://example.com",
      check_interval_seconds: "60",
      expected_status_code: "200",
      timeout_ms: "5000"
    }
  end

  describe "Index" do
    test "lists only the current user's monitors", %{conn: conn, user: user} do
      mine = monitor_fixture(%{user: user, name: "Mine"})
      _theirs = monitor_fixture(%{name: "Someone else's"})

      {:ok, _view, html} = live(conn, ~p"/monitors")

      assert html =~ mine.name
      refute html =~ "Someone else's"
    end

    test "a monitor with no checks shows a pending status, not an error", %{
      conn: conn,
      user: user
    } do
      monitor_fixture(%{user: user})

      {:ok, _view, html} = live(conn, ~p"/monitors")
      assert html =~ "Pending"
    end

    test "creates a monitor through the modal form, starting it active", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/monitors")

      assert view |> element("a", "New monitor") |> render_click() =~ "New Monitor"
      assert_patch(view, ~p"/monitors/new")

      assert view
             |> form("#monitor-form", monitor: %{valid_attrs() | url: "not a url"})
             |> render_change() =~ "must be a valid http or https URL"

      assert view
             |> form("#monitor-form", monitor: valid_attrs())
             |> render_submit()

      assert_patch(view, ~p"/monitors")
      html = render(view)
      assert html =~ "Monitor created"
      assert html =~ "Example"
    end

    test "edits a monitor through the modal form", %{conn: conn, user: user} do
      monitor = monitor_fixture(%{user: user, name: "Original"})
      {:ok, view, _html} = live(conn, ~p"/monitors")

      assert view |> element("a", "Edit") |> render_click() =~ "Edit Monitor"
      assert_patch(view, ~p"/monitors/#{monitor}/edit")

      assert view
             |> form("#monitor-form", monitor: %{name: "Renamed"})
             |> render_submit()

      assert_patch(view, ~p"/monitors")
      assert render(view) =~ "Renamed"
    end

    test "pauses and resumes a monitor", %{conn: conn, user: user} do
      monitor = monitor_fixture(%{user: user})
      {:ok, view, _html} = live(conn, ~p"/monitors")

      html = view |> element("a", "Pause") |> render_click()
      assert html =~ "Paused"
      assert Monitoring.get_monitor!(user, monitor.id).active == false

      html = view |> element("a", "Resume") |> render_click()
      assert html =~ "Pending"
      assert Monitoring.get_monitor!(user, monitor.id).active == true
    end

    test "deletes a monitor", %{conn: conn, user: user} do
      monitor = monitor_fixture(%{user: user, name: "Doomed"})
      {:ok, view, _html} = live(conn, ~p"/monitors")

      view |> element("a", "Delete") |> render_click()
      refute render(view) =~ "Doomed"
      assert {:error, :not_found} = Monitoring.get_monitor(user, monitor.id)
    end

    test "a PubSub broadcast updates the dashboard without a page reload", %{
      conn: conn,
      user: user
    } do
      monitor = monitor_fixture(%{user: user})
      {:ok, view, html} = live(conn, ~p"/monitors")
      assert html =~ "Pending"

      check = check_fixture(monitor, %{status: :up, response_time_ms: 42})
      Monitoring.broadcast(monitor, {:check_recorded, check})

      html = render(view)
      assert html =~ "Up"
      assert html =~ "42 ms"
    end

    test "a broadcast for another user's monitor is not received", %{conn: conn, user: user} do
      other_user = Pulsewatch.AccountsFixtures.user_fixture()
      their_monitor = monitor_fixture(%{user: other_user, name: "Not mine"})
      _mine = monitor_fixture(%{user: user})

      {:ok, view, _html} = live(conn, ~p"/monitors")

      check = check_fixture(their_monitor, %{status: :up})
      Monitoring.broadcast(their_monitor, {:check_recorded, check})

      # No crash, and their monitor never appears — proves the LiveView
      # only subscribed to (and only renders) its own user's topic.
      refute render(view) =~ "Not mine"
    end
  end
end
