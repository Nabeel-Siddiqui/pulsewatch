defmodule PulsewatchWeb.MonitorLive.ShowTest do
  use PulsewatchWeb.ConnCase

  import Phoenix.LiveViewTest
  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Monitoring

  setup :register_and_log_in_user

  test "shows monitor details, chart canvas, incidents, and recent checks", %{
    conn: conn,
    user: user
  } do
    monitor = monitor_fixture(%{user: user, name: "My Site"})
    check_fixture(monitor, %{status: :up, response_time_ms: 55})
    {:ok, incident} = Monitoring.open_incident(monitor)

    {:ok, _view, html} = live(conn, ~p"/monitors/#{monitor}")

    assert html =~ "My Site"
    assert html =~ ~s(id="response-time-chart")
    assert html =~ ~s(phx-hook="ResponseTimeChart")
    assert html =~ "55 ms"
    assert html =~ format_time(incident.started_at)
  end

  test "a monitor a different user owns renders a 404-style not-found", %{conn: conn} do
    other = monitor_fixture()

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/monitors/#{other}")
    end
  end

  test "edits the monitor from the detail page", %{conn: conn, user: user} do
    monitor = monitor_fixture(%{user: user, name: "Before"})
    {:ok, view, _html} = live(conn, ~p"/monitors/#{monitor}")

    assert view |> element("a", "Edit") |> render_click() =~ "Edit Before"
    assert_patch(view, ~p"/monitors/#{monitor}/show/edit")

    assert view
           |> form("#monitor-form", monitor: %{name: "After"})
           |> render_submit()

    assert_patch(view, ~p"/monitors/#{monitor}")
    assert render(view) =~ "After"
  end

  test "pauses, resumes, and deletes from the detail page", %{conn: conn, user: user} do
    monitor = monitor_fixture(%{user: user})
    {:ok, view, _html} = live(conn, ~p"/monitors/#{monitor}")

    assert view |> element("button", "Pause") |> render_click() =~ "Paused"
    assert Monitoring.get_monitor!(user, monitor.id).active == false

    assert view |> element("button", "Resume") |> render_click() =~ "Active"
    assert Monitoring.get_monitor!(user, monitor.id).active == true

    {:error, {:live_redirect, %{to: path}}} =
      view |> element("button", "Delete") |> render_click()

    assert path == ~p"/monitors"
    assert {:error, :not_found} = Monitoring.get_monitor(user, monitor.id)
  end

  test "a :check_recorded broadcast prepends to the recent-checks stream", %{
    conn: conn,
    user: user
  } do
    monitor = monitor_fixture(%{user: user})
    {:ok, view, _html} = live(conn, ~p"/monitors/#{monitor}")

    check = check_fixture(monitor, %{status: :down, error_message: "connection refused"})
    Monitoring.broadcast(monitor, {:check_recorded, check})

    assert render(view) =~ "connection refused"
  end

  test "an :incident_opened broadcast adds it to the incident list live", %{
    conn: conn,
    user: user
  } do
    monitor = monitor_fixture(%{user: user})
    {:ok, view, html} = live(conn, ~p"/monitors/#{monitor}")
    refute html =~ "Ongoing"

    {:ok, incident} = Monitoring.open_incident(monitor)
    Monitoring.broadcast(monitor, {:incident_opened, incident})

    assert render(view) =~ "Ongoing"
  end

  test "an :incident_resolved broadcast updates that row from Ongoing to resolved", %{
    conn: conn,
    user: user
  } do
    monitor = monitor_fixture(%{user: user})
    {:ok, incident} = Monitoring.open_incident(monitor)
    {:ok, view, html} = live(conn, ~p"/monitors/#{monitor}")
    assert html =~ "Ongoing"

    {:ok, resolved} = Monitoring.resolve_incident(incident)
    Monitoring.broadcast(monitor, {:incident_resolved, resolved})

    refute render(view) =~ "Ongoing"
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
end
