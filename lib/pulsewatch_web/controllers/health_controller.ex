defmodule PulsewatchWeb.HealthController do
  use PulsewatchWeb, :controller

  alias Pulsewatch.Monitoring.MonitorSupervisor
  alias Pulsewatch.Repo

  @doc """
  Unauthenticated liveness/readiness check: database connectivity and
  how many monitor workers are currently running. Meant for a deploy
  platform's health check, not a human — no auth, minimal payload.
  """
  def show(conn, _params) do
    workers = MonitorSupervisor.worker_count()

    case database_status() do
      :ok ->
        json(conn, %{status: "ok", database: "ok", workers: workers})

      :error ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "degraded", database: "error", workers: workers})
    end
  end

  defp database_status do
    Repo.query!("SELECT 1")
    :ok
  rescue
    # Deliberately broad and unlogged: a DB connectivity failure is
    # exactly the condition this endpoint exists to report, not an
    # unexpected bug — the response body already communicates it to
    # whatever's polling (a deploy platform's health check), and logging
    # every blip here would just be noise on top of Ecto's own logging.
    _ -> :error
  end
end
