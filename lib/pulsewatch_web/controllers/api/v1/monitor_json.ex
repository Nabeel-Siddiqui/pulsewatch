defmodule PulsewatchWeb.Api.V1.MonitorJSON do
  @moduledoc "Renders `Monitor` structs as JSON for the /api/v1 API."

  alias Pulsewatch.Monitoring.Monitor

  def index(%{monitors: monitors}) do
    %{data: Enum.map(monitors, &data/1)}
  end

  def show(%{monitor: monitor}) do
    %{data: data(monitor)}
  end

  defp data(%Monitor{} = monitor) do
    %{
      id: monitor.id,
      name: monitor.name,
      url: monitor.url,
      check_interval_seconds: monitor.check_interval_seconds,
      expected_status_code: monitor.expected_status_code,
      timeout_ms: monitor.timeout_ms,
      active: monitor.active,
      webhook_url: monitor.webhook_url,
      inserted_at: monitor.inserted_at
    }
  end
end
