defmodule PulsewatchWeb.Api.V1.IncidentJSON do
  @moduledoc "Renders `Incident` structs as JSON for the /api/v1 API."

  alias Pulsewatch.Monitoring.Incident

  def index(%{incidents: incidents}) do
    %{data: Enum.map(incidents, &data/1)}
  end

  defp data(%Incident{} = incident) do
    %{
      id: incident.id,
      started_at: incident.started_at,
      resolved_at: incident.resolved_at,
      ai_summary: incident.ai_summary
    }
  end
end
