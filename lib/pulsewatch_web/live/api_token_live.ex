defmodule PulsewatchWeb.ApiTokenLive do
  use PulsewatchWeb, :live_view

  alias Pulsewatch.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "API tokens")
     |> assign(:new_token, nil)
     |> assign(:form, to_form(%{"name" => ""}))
     |> assign(:tokens, Accounts.list_api_tokens(socket.assigns.current_user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      API tokens
      <:subtitle>
        Personal access tokens for the JSON API (<code>/api/v1</code>). See
        <.link navigate={~p"/api/swaggerui"} target="_blank" class="underline">
          the API docs
        </.link>
        for available endpoints.
      </:subtitle>
    </.header>

    <div
      :if={@new_token}
      class="mt-6 rounded-lg border border-amber-300 bg-amber-50 p-4"
      id="new-token-banner"
    >
      <p class="text-sm font-semibold text-amber-900">
        Copy this token now — it won't be shown again.
      </p>
      <code class="mt-2 block break-all rounded bg-white p-2 text-sm">{@new_token}</code>
    </div>

    <.simple_form for={@form} id="new-token-form" phx-submit="create">
      <.input field={@form[:name]} type="text" label="Token name" placeholder="e.g. CI pipeline" />
      <:actions>
        <.button phx-disable-with="Creating...">Generate token</.button>
      </:actions>
    </.simple_form>

    <.table id="tokens" rows={@tokens}>
      <:col :let={token} label="Name">{token.name}</:col>
      <:col :let={token} label="Created">{format_date(token.inserted_at)}</:col>
      <:col :let={token} label="Last used">
        {(token.last_used_at && format_date(token.last_used_at)) || "Never"}
      </:col>
      <:action :let={token}>
        <.link
          phx-click="revoke"
          phx-value-id={token.id}
          data-confirm="Revoke this token? Anything using it will stop working immediately."
        >
          Revoke
        </.link>
      </:action>
    </.table>
    """
  end

  @impl true
  def handle_event("create", %{"name" => name}, socket) do
    case Accounts.create_api_token(socket.assigns.current_user, name) do
      {:ok, token, _api_token} ->
        {:noreply,
         socket
         |> assign(:new_token, token)
         |> assign(:form, to_form(%{"name" => ""}))
         |> assign(:tokens, Accounts.list_api_tokens(socket.assigns.current_user))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    token =
      Enum.find(socket.assigns.tokens, &(&1.id == String.to_integer(id)))

    if token do
      {:ok, _} = Accounts.revoke_api_token(user, token)
    end

    {:noreply,
     socket
     |> assign(:new_token, nil)
     |> assign(:tokens, Accounts.list_api_tokens(user))}
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
