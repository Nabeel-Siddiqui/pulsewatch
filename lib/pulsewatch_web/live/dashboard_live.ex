defmodule PulsewatchWeb.DashboardLive do
  use PulsewatchWeb, :live_view

  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.{Engine, Monitor}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      :ok = Monitoring.subscribe_to_user_monitors(user)
    end

    {:ok, assign(socket, :rows, Monitoring.dashboard_rows(user))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Monitors") |> assign(:monitor, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket |> assign(:page_title, "New Monitor") |> assign(:monitor, %Monitor{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    monitor = Monitoring.get_monitor!(socket.assigns.current_user, id)
    socket |> assign(:page_title, "Edit Monitor") |> assign(:monitor, monitor)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Monitors
      <:subtitle>Every site you're watching, with its current status and 24h uptime.</:subtitle>
      <:actions>
        <.link patch={~p"/monitors/new"}>
          <.button>New monitor</.button>
        </.link>
      </:actions>
    </.header>

    <.table id="monitors" rows={@rows}>
      <:col :let={row} label="Name">
        <.link navigate={~p"/monitors/#{row.monitor}"} class="font-semibold text-zinc-900">
          {row.monitor.name}
        </.link>
      </:col>
      <:col :let={row} label="URL">{row.monitor.url}</:col>
      <:col :let={row} label="Status">
        <span class={status_class(row.status, row.monitor.active)}>
          {status_label(row.status, row.monitor.active)}
        </span>
      </:col>
      <:col :let={row} label="Last response">
        {row.last_response_time_ms && "#{row.last_response_time_ms} ms"}
      </:col>
      <:col :let={row} label="24h uptime">
        {row.uptime_pct && "#{row.uptime_pct}%"}
      </:col>
      <:action :let={row}>
        <.link patch={~p"/monitors/#{row.monitor}/edit"}>Edit</.link>
      </:action>
      <:action :let={row}>
        <.link :if={row.monitor.active} phx-click="pause" phx-value-id={row.monitor.id}>
          Pause
        </.link>
        <.link :if={not row.monitor.active} phx-click="resume" phx-value-id={row.monitor.id}>
          Resume
        </.link>
      </:action>
      <:action :let={row}>
        <.link
          phx-click="delete"
          phx-value-id={row.monitor.id}
          data-confirm={"Delete #{row.monitor.name}?"}
        >
          Delete
        </.link>
      </:action>
    </.table>

    <.modal
      :if={@live_action in [:new, :edit]}
      id="monitor-modal"
      show
      on_cancel={JS.patch(~p"/monitors")}
    >
      <.live_component
        module={PulsewatchWeb.MonitorLive.FormComponent}
        id={@monitor.id || :new}
        title={@page_title}
        action={@live_action}
        monitor={@monitor}
        current_user={@current_user}
        patch={~p"/monitors"}
      />
    </.modal>
    """
  end

  @impl true
  def handle_event("pause", %{"id" => id}, socket) do
    monitor = Monitoring.get_monitor!(socket.assigns.current_user, id)
    {:ok, _monitor} = Engine.pause_monitor(socket.assigns.current_user, monitor)
    {:noreply, refresh(socket)}
  end

  def handle_event("resume", %{"id" => id}, socket) do
    monitor = Monitoring.get_monitor!(socket.assigns.current_user, id)
    {:ok, _monitor} = Engine.resume_monitor(socket.assigns.current_user, monitor)
    {:noreply, refresh(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    monitor = Monitoring.get_monitor!(socket.assigns.current_user, id)
    {:ok, _monitor} = Engine.delete_monitor(socket.assigns.current_user, monitor)
    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_info({:check_recorded, _check}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:incident_opened, _incident}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:incident_resolved, _incident}, socket), do: {:noreply, refresh(socket)}

  def handle_info({PulsewatchWeb.MonitorLive.FormComponent, {:saved, _monitor}}, socket) do
    {:noreply, refresh(socket)}
  end

  defp refresh(socket) do
    assign(socket, :rows, Monitoring.dashboard_rows(socket.assigns.current_user))
  end

  defp status_label(_status, false), do: "Paused"
  defp status_label(nil, true), do: "Pending"
  defp status_label(:up, true), do: "Up"
  defp status_label(:down, true), do: "Down"

  defp status_class(_status, false), do: "text-zinc-400"
  defp status_class(nil, true), do: "text-zinc-500"
  defp status_class(:up, true), do: "text-green-700 font-semibold"
  defp status_class(:down, true), do: "text-red-700 font-semibold"
end
