defmodule PulsewatchWeb.Api.V1.CheckJSON do
  @moduledoc "Renders `Check` structs as JSON for the /api/v1 API."

  alias Pulsewatch.Monitoring.Check

  def index(%{checks: checks}) do
    %{data: Enum.map(checks, &data/1)}
  end

  defp data(%Check{} = check) do
    %{
      id: check.id,
      status: check.status,
      status_code: check.status_code,
      response_time_ms: check.response_time_ms,
      error_message: check.error_message,
      checked_at: check.checked_at
    }
  end
end
