defmodule Pulsewatch.Monitoring.NodeLockTest do
  use Pulsewatch.DataCase, async: true

  alias Pulsewatch.Monitoring.NodeLock

  # Each test starts its own unnamed NodeLock instances (rather than
  # using the application's singleton) to stand in for separate nodes,
  # each with its own dedicated Postgres connection — exactly how two
  # real nodes in a cluster would each hold their own connection. A
  # fresh, globally-unique lock id per test keeps these from colliding
  # with each other or with the real singleton, since advisory locks are
  # global to the whole database, not scoped to a connection's session
  # in the sense of being private.
  defp unique_id, do: System.unique_integer([:positive])

  test "a lock held by one connection is denied to a second, and freed once released" do
    monitor_id = unique_id()
    {:ok, node_a} = NodeLock.start_link(name: nil)
    {:ok, node_b} = NodeLock.start_link(name: nil)

    assert NodeLock.try_lock(monitor_id, node_a)
    refute NodeLock.try_lock(monitor_id, node_b)

    :ok = NodeLock.unlock(monitor_id, node_a)

    assert NodeLock.try_lock(monitor_id, node_b)
  end

  test "re-acquiring a lock already held by the same connection succeeds" do
    monitor_id = unique_id()
    {:ok, node_a} = NodeLock.start_link(name: nil)

    assert NodeLock.try_lock(monitor_id, node_a)
    assert NodeLock.try_lock(monitor_id, node_a)
  end

  test "unlocking a lock this connection never held is a no-op, not an error" do
    monitor_id = unique_id()
    {:ok, node_a} = NodeLock.start_link(name: nil)

    assert :ok = NodeLock.unlock(monitor_id, node_a)
  end
end
