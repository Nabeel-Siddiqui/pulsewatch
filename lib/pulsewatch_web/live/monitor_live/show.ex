defmodule PulsewatchWeb.MonitorLive.Show do
  use PulsewatchWeb, :live_view

  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.Engine

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    monitor = Monitoring.get_monitor!(socket.assigns.current_user, id)

    if connected?(socket) do
      :ok = Monitoring.subscribe_to_monitor(monitor)
    end

    checks_24h = Monitoring.list_checks_since(monitor, 24)

    {:ok,
     socket
     |> assign(:monitor, monitor)
     |> assign(:incidents, Monitoring.list_incidents(monitor))
     |> assign(:chart_points, Enum.map(checks_24h, &chart_point/1))
     |> stream(:checks, checks_24h |> Enum.reverse() |> Enum.take(50))}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :show) do
    assign(socket, :page_title, socket.assigns.monitor.name)
  end

  defp apply_action(socket, :edit) do
    assign(socket, :page_title, "Edit #{socket.assigns.monitor.name}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@monitor.name}
      <:subtitle>{@monitor.url}</:subtitle>
      <:actions>
        <.link patch={~p"/monitors/#{@monitor}/show/edit"}>
          <.button>Edit</.button>
        </.link>
        <.button :if={@monitor.active} phx-click="pause">Pause</.button>
        <.button :if={not @monitor.active} phx-click="resume">Resume</.button>
        <.button
          phx-click="delete"
          data-confirm="Delete this monitor?"
          class="bg-red-600 hover:bg-red-500"
        >
          Delete
        </.button>
        <.back navigate={~p"/monitors"}>Back to monitors</.back>
      </:actions>
    </.header>

    <.list>
      <:item title="Status">{(@monitor.active && "Active") || "Paused"}</:item>
      <:item title="Check interval">{@monitor.check_interval_seconds}s</:item>
      <:item title="Expected status">{@monitor.expected_status_code}</:item>
      <:item title="Timeout">{@monitor.timeout_ms}ms</:item>
      <:item title="Webhook">{@monitor.webhook_url || "—"}</:item>
    </.list>

    <.header class="mt-10">Response time (last 24h)</.header>
    <canvas
      id="response-time-chart"
      phx-hook="ResponseTimeChart"
      phx-update="ignore"
      data-points={Jason.encode!(@chart_points)}
    >
    </canvas>

    <.header class="mt-10">Incidents</.header>
    <.table id="incidents" rows={@incidents}>
      <:col :let={incident} label="Started">{format_time(incident.started_at)}</:col>
      <:col :let={incident} label="Resolved">
        {(incident.resolved_at && format_time(incident.resolved_at)) || "Ongoing"}
      </:col>
      <:col :let={incident} label="Duration">{duration(incident)}</:col>
      <:col :let={incident} label="AI summary">{incident.ai_summary || "—"}</:col>
    </.table>

    <.header class="mt-10">Recent checks</.header>
    <.table id="checks" rows={@streams.checks}>
      <:col :let={{_id, check}} label="Time">{format_time(check.checked_at)}</:col>
      <:col :let={{_id, check}} label="Status">{check.status}</:col>
      <:col :let={{_id, check}} label="HTTP status">{check.status_code || "—"}</:col>
      <:col :let={{_id, check}} label="Response time">
        {(check.response_time_ms && "#{check.response_time_ms} ms") || "—"}
      </:col>
      <:col :let={{_id, check}} label="Error">{check.error_message || "—"}</:col>
    </.table>

    <.modal
      :if={@live_action == :edit}
      id="monitor-modal"
      show
      on_cancel={JS.patch(~p"/monitors/#{@monitor}")}
    >
      <.live_component
        module={PulsewatchWeb.MonitorLive.FormComponent}
        id={@monitor.id}
        title={@page_title}
        action={@live_action}
        monitor={@monitor}
        current_user={@current_user}
        patch={~p"/monitors/#{@monitor}"}
      />
    </.modal>
    """
  end

  @impl true
  def handle_event("pause", _params, socket) do
    {:ok, monitor} = Engine.pause_monitor(socket.assigns.current_user, socket.assigns.monitor)
    {:noreply, assign(socket, :monitor, monitor)}
  end

  def handle_event("resume", _params, socket) do
    {:ok, monitor} = Engine.resume_monitor(socket.assigns.current_user, socket.assigns.monitor)
    {:noreply, assign(socket, :monitor, monitor)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _monitor} = Engine.delete_monitor(socket.assigns.current_user, socket.assigns.monitor)

    {:noreply,
     socket
     |> put_flash(:info, "Monitor deleted")
     |> push_navigate(to: ~p"/monitors")}
  end

  @impl true
  def handle_info({:check_recorded, check}, socket) do
    socket =
      socket
      |> stream_insert(:checks, check, at: 0, limit: 50)
      |> push_event("new-chart-point", chart_point(check))

    {:noreply, socket}
  end

  def handle_info({:incident_opened, incident}, socket) do
    {:noreply, update(socket, :incidents, &[incident | &1])}
  end

  def handle_info({:incident_resolved, resolved}, socket) do
    incidents =
      Enum.map(socket.assigns.incidents, &if(&1.id == resolved.id, do: resolved, else: &1))

    {:noreply, assign(socket, :incidents, incidents)}
  end

  def handle_info({PulsewatchWeb.MonitorLive.FormComponent, {:saved, monitor}}, socket) do
    {:noreply, assign(socket, :monitor, monitor)}
  end

  defp chart_point(check) do
    %{x: format_time(check.checked_at), y: check.response_time_ms}
  end

  defp format_time(nil), do: nil
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")

  defp duration(%{resolved_at: nil, started_at: started_at}) do
    seconds = DateTime.diff(DateTime.utc_now(), started_at)
    "#{div(seconds, 60)}m (ongoing)"
  end

  defp duration(%{resolved_at: resolved_at, started_at: started_at}) do
    seconds = DateTime.diff(resolved_at, started_at)
    "#{div(seconds, 60)}m"
  end
end
