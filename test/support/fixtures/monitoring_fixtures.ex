defmodule Pulsewatch.MonitoringFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Pulsewatch.Monitoring` context.
  """

  alias Pulsewatch.Accounts.User

  @doc "Generates a monitor owned by `user` (a fresh user is created if none is given)."
  def monitor_fixture(attrs \\ %{}) do
    {user, attrs} = pop_owner(attrs)

    {:ok, monitor} =
      attrs
      |> Enum.into(%{
        active: true,
        check_interval_seconds: 60,
        expected_status_code: 200,
        name: "some monitor",
        timeout_ms: 5_000,
        url: "https://example.com"
      })
      |> then(&Pulsewatch.Monitoring.create_monitor(user, &1))

    monitor
  end

  @doc "Generates a check for `monitor` (required via `attrs[:monitor]` or the `monitor` arg)."
  def check_fixture(monitor, attrs \\ %{}) do
    {:ok, check} =
      attrs
      |> Enum.into(%{
        checked_at: DateTime.utc_now(),
        response_time_ms: 120,
        status: :up,
        status_code: 200
      })
      |> then(&Pulsewatch.Monitoring.create_check(monitor, &1))

    check
  end

  @doc "Opens (and returns) an incident for `monitor`."
  def incident_fixture(monitor, started_at \\ DateTime.utc_now()) do
    {:ok, incident} = Pulsewatch.Monitoring.open_incident(monitor, started_at)
    incident
  end

  defp pop_owner(attrs) do
    case Map.pop(attrs, :user) do
      {%User{} = user, attrs} -> {user, attrs}
      {nil, attrs} -> {Pulsewatch.AccountsFixtures.user_fixture(), attrs}
    end
  end
end
