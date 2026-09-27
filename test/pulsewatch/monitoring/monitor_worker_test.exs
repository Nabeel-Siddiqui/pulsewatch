defmodule Pulsewatch.Monitoring.MonitorWorkerTest do
  use Pulsewatch.DataCase, async: true

  import Mox
  import Pulsewatch.MonitoringFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.MonitorWorker

  setup :verify_on_exit!

  # The worker's init/1 schedules the first check with jitter, but tests
  # drive `:check` manually via `send/2` instead of waiting on a real
  # timer — deterministic and fast, and it exercises the exact same
  # handle_info/2 clause a real timer fires.
  defp start_worker!(monitor) do
    pid = start_supervised!({MonitorWorker, monitor}, id: monitor.id)
    allow(Pulsewatch.Monitoring.HttpClientMock, self(), pid)
    Sandbox.allow(Pulsewatch.Repo, self(), pid)
    pid
  end

  defp check!(pid) do
    send(pid, :check)
    # handle_info/2 does DB writes synchronously before replying, so a
    # synchronous call after it is enough to know the check completed.
    :sys.get_state(pid)
  end

  test "an :up check keeps consecutive_failures at 0" do
    monitor = monitor_fixture()
    pid = start_worker!(monitor)
    expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:ok, 200} end)

    state = check!(pid)
    assert state.consecutive_failures == 0
    assert [%{status: :up}] = Monitoring.list_recent_checks(monitor)
  end

  test "consecutive failures accumulate in the worker's state across checks" do
    monitor = monitor_fixture()
    pid = start_worker!(monitor)

    expect(Pulsewatch.Monitoring.HttpClientMock, :get, 3, fn _url, _timeout ->
      {:error, :timeout}
    end)

    assert %{consecutive_failures: 1} = check!(pid)
    assert %{consecutive_failures: 2} = check!(pid)
    assert %{consecutive_failures: 3} = check!(pid)

    assert {:ok, _incident} = Monitoring.get_open_incident(monitor)
    assert length(Monitoring.list_recent_checks(monitor)) == 3
  end

  test "recovering after being down resets consecutive_failures to 0" do
    monitor = monitor_fixture()
    pid = start_worker!(monitor)

    expect(Pulsewatch.Monitoring.HttpClientMock, :get, 2, fn _url, _timeout ->
      {:error, :timeout}
    end)

    expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:ok, 200} end)

    check!(pid)
    check!(pid)
    assert {:ok, _incident} = Monitoring.get_open_incident(monitor)

    assert %{consecutive_failures: 0} = check!(pid)
    assert {:error, :not_found} = Monitoring.get_open_incident(monitor)
  end

  test "a crashing worker doesn't affect a sibling worker's state" do
    monitor_a = monitor_fixture()
    monitor_b = monitor_fixture()
    pid_a = start_worker!(monitor_a)
    pid_b = start_worker!(monitor_b)

    expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:error, :timeout} end)

    check!(pid_a)

    # Crash A directly (not via the supervisor's restart path — this test
    # only cares that A's failure is invisible to B).
    Process.exit(pid_a, :kill)

    assert %{consecutive_failures: 0} = :sys.get_state(pid_b)
    assert Process.alive?(pid_b)
  end
end
