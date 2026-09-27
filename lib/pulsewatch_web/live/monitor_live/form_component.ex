defmodule PulsewatchWeb.MonitorLive.FormComponent do
  use PulsewatchWeb, :live_component

  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.Engine

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>A check runs every 30-3600 seconds against the URL below.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="monitor-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:url]} type="text" label="URL" placeholder="https://example.com" />
        <.input field={@form[:check_interval_seconds]} type="number" label="Check interval (seconds)" />
        <.input field={@form[:expected_status_code]} type="number" label="Expected status code" />
        <.input field={@form[:timeout_ms]} type="number" label="Timeout (ms)" />
        <.input
          field={@form[:webhook_url]}
          type="text"
          label="Webhook URL (optional)"
          placeholder="https://hooks.example.com/..."
        />
        <:actions>
          <.button phx-disable-with="Saving...">Save monitor</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{monitor: monitor} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn -> to_form(Monitoring.change_monitor(monitor)) end)}
  end

  @impl true
  def handle_event("validate", %{"monitor" => monitor_params}, socket) do
    changeset = Monitoring.change_monitor(socket.assigns.monitor, monitor_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"monitor" => monitor_params}, socket) do
    save_monitor(socket, socket.assigns.action, monitor_params)
  end

  defp save_monitor(socket, :edit, monitor_params) do
    case Engine.update_monitor(
           socket.assigns.current_user,
           socket.assigns.monitor,
           monitor_params
         ) do
      {:ok, monitor} ->
        notify_parent({:saved, monitor})

        {:noreply,
         socket
         |> put_flash(:info, "Monitor updated")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_monitor(socket, :new, monitor_params) do
    case Engine.create_monitor(socket.assigns.current_user, monitor_params) do
      {:ok, monitor} ->
        notify_parent({:saved, monitor})

        {:noreply,
         socket
         |> put_flash(:info, "Monitor created")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
