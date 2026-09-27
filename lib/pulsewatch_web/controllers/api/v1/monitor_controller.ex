defmodule PulsewatchWeb.Api.V1.MonitorController do
  use PulsewatchWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback PulsewatchWeb.Api.FallbackController

  alias Pulsewatch.Monitoring
  alias PulsewatchWeb.Schemas

  tags ["monitors"]

  operation :index,
    summary: "List your monitors",
    responses: [
      ok: {"Monitors", "application/json", Schemas.MonitorsResponse}
    ]

  def index(conn, _params) do
    monitors = Monitoring.list_monitors(conn.assigns.current_user)
    render(conn, :index, monitors: monitors)
  end

  operation :show,
    summary: "Get a single monitor",
    parameters: [
      id: [in: :path, description: "Monitor ID", type: :integer, example: 1]
    ],
    responses: [
      ok: {"Monitor", "application/json", Schemas.MonitorResponse},
      not_found: {"Not found", "application/json", Schemas.ErrorResponse}
    ]

  def show(conn, %{"id" => id}) do
    with {:ok, monitor} <- Monitoring.get_monitor(conn.assigns.current_user, id) do
      render(conn, :show, monitor: monitor)
    end
  end

  operation :checks,
    summary: "List a monitor's recent checks",
    parameters: [
      id: [in: :path, description: "Monitor ID", type: :integer, example: 1],
      limit: [
        in: :query,
        description: "Max checks to return (1-100, default 20)",
        type: :integer,
        example: 20
      ]
    ],
    responses: [
      ok: {"Checks", "application/json", Schemas.ChecksResponse},
      not_found: {"Not found", "application/json", Schemas.ErrorResponse}
    ]

  def checks(conn, %{"id" => id} = params) do
    with {:ok, monitor} <- Monitoring.get_monitor(conn.assigns.current_user, id) do
      limit = parse_limit(params["limit"])

      conn
      |> put_view(json: PulsewatchWeb.Api.V1.CheckJSON)
      |> render(:index, checks: Monitoring.list_recent_checks(monitor, limit))
    end
  end

  operation :incidents,
    summary: "List a monitor's incidents",
    parameters: [
      id: [in: :path, description: "Monitor ID", type: :integer, example: 1]
    ],
    responses: [
      ok: {"Incidents", "application/json", Schemas.IncidentsResponse},
      not_found: {"Not found", "application/json", Schemas.ErrorResponse}
    ]

  def incidents(conn, %{"id" => id}) do
    with {:ok, monitor} <- Monitoring.get_monitor(conn.assigns.current_user, id) do
      conn
      |> put_view(json: PulsewatchWeb.Api.V1.IncidentJSON)
      |> render(:index, incidents: Monitoring.list_incidents(monitor))
    end
  end

  defp parse_limit(nil), do: 20

  defp parse_limit(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 and n <= 100 -> n
      _ -> 20
    end
  end
end
