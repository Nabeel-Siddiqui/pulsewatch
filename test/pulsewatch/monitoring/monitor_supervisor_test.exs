defmodule Pulsewatch.Monitoring.MonitorSupervisorTest do
  use Pulsewatch.DataCase, async: true

  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Monitoring.{MonitorSupervisor, NodeLock}

  # None of these tests wait long enough for a worker's first check to
  # fire (it's scheduled 0-5s out with jitter) — they're only exercising
  # supervision (start/stop/restart/crash-isolation), not check behavior,
  # so no HttpClient mock expectations are needed here.
  #
  # MonitorSupervisor is the single, application-wide DynamicSupervisor
  # (it's part of the real supervision tree, not something each test gets
  # its own copy of), so every worker a test starts must be stopped again
  # on exit — otherwise it leaks into later tests and its check timer can
  # eventually fire against a sandbox connection that's already been
  # checked back in.
  defp start_and_track!(monitor) do
    :ok = MonitorSupervisor.start_worker(monitor)
    on_exit(fn -> MonitorSupervisor.stop_worker(monitor.id) end)
    monitor
  end

  defp registered?(monitor_id) do
    case Registry.lookup(Pulsewatch.Monitoring.Registry, monitor_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  test "start_worker/1 registers a findable process" do
    monitor = monitor_fixture() |> start_and_track!()

    assert registered?(monitor.id)
  end

  test "start_worker/1 is idempotent — starting twice doesn't error or duplicate" do
    monitor = monitor_fixture() |> start_and_track!()
    [{pid, _}] = Registry.lookup(Pulsewatch.Monitoring.Registry, monitor.id)

    :ok = MonitorSupervisor.start_worker(monitor)
    assert [{^pid, _}] = Registry.lookup(Pulsewatch.Monitoring.Registry, monitor.id)
  end

  test "stop_worker/1 removes the process" do
    monitor = monitor_fixture() |> start_and_track!()
    assert registered?(monitor.id)

    :ok = MonitorSupervisor.stop_worker(monitor.id)

    # terminate_child/2 blocks until the supervisor's own monitor sees the
    # child exit, but Registry cleans up via a separate monitor of its
    # own — that can trail by a message-queue tick, so poll instead of
    # asserting immediately.
    wait_until(fn -> not registered?(monitor.id) end)
  end

  test "stop_worker/1 on an id with no running worker is a no-op" do
    assert :ok = MonitorSupervisor.stop_worker(-1)
  end

  test "restart_worker/1 replaces the process with a new one" do
    monitor = monitor_fixture() |> start_and_track!()
    [{original_pid, _}] = Registry.lookup(Pulsewatch.Monitoring.Registry, monitor.id)

    :ok = MonitorSupervisor.restart_worker(monitor)
    [{new_pid, _}] = Registry.lookup(Pulsewatch.Monitoring.Registry, monitor.id)

    assert new_pid != original_pid
    refute Process.alive?(original_pid)
  end

  test "a crashing worker is restarted by the supervisor without affecting a sibling" do
    monitor_a = monitor_fixture() |> start_and_track!()
    monitor_b = monitor_fixture() |> start_and_track!()

    [{pid_a, _}] = Registry.lookup(Pulsewatch.Monitoring.Registry, monitor_a.id)
    [{pid_b, _}] = Registry.lookup(Pulsewatch.Monitoring.Registry, monitor_b.id)

    Process.exit(pid_a, :kill)
    # DynamicSupervisor restarts asynchronously — wait for the Registry
    # entry to change rather than sleeping a fixed amount.
    wait_until(fn ->
      case Registry.lookup(Pulsewatch.Monitoring.Registry, monitor_a.id) do
        [{^pid_a, _}] -> false
        [{_new_pid, _}] -> true
        [] -> false
      end
    end)

    assert Process.alive?(pid_b)
    assert [{^pid_b, _}] = Registry.lookup(Pulsewatch.Monitoring.Registry, monitor_b.id)
  end

  test "does not start a worker locally when another node already owns the monitor's lock" do
    monitor = monitor_fixture()
    {:ok, other_node} = NodeLock.start_link(name: nil)
    true = NodeLock.try_lock(monitor.id, other_node)

    :ok = MonitorSupervisor.start_worker(monitor)

    refute registered?(monitor.id)

    NodeLock.unlock(monitor.id, other_node)
  end

  test "start_all_active_monitors/0 starts a worker per active monitor and skips paused ones" do
    active = monitor_fixture(%{active: true})
    paused = monitor_fixture(%{active: false})
    on_exit(fn -> MonitorSupervisor.stop_worker(active.id) end)

    :ok = MonitorSupervisor.start_all_active_monitors()

    assert registered?(active.id)
    refute registered?(paused.id)
  end

  defp wait_until(fun, attempts \\ 50)
  defp wait_until(_fun, 0), do: flunk("condition not met in time")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end
end
