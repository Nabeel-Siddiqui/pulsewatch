defmodule Pulsewatch.Monitoring.NodeLock do
  @moduledoc """
  Cluster-wide mutual exclusion over which node runs a given monitor's
  worker, using Postgres session-level advisory locks
  (`pg_try_advisory_lock`/`pg_advisory_unlock`).

  ## The problem

  `dns_cluster` (already wired in `Pulsewatch.Application`) connects
  nodes into one Erlang cluster automatically at boot, but nothing about
  that makes `Pulsewatch.Monitoring.Registry` or `MonitorSupervisor`
  cluster-aware — both are local to each node. Left alone,
  `MonitorSupervisor.start_all_active_monitors/0` running on two nodes
  means every monitor gets checked twice, on every interval, and every
  incident gets alerted on twice. Something has to make "which node owns
  this monitor" cluster-wide, single-source-of-truth information.

  ## Why advisory locks instead of Horde

  Horde (a CRDT-backed distributed Registry/DynamicSupervisor) is the
  more complete answer to this class of problem — it would also
  rebalance automatically when a node joins or leaves. It was
  deliberately not used here for two reasons. First, a CRDT converges
  *eventually*, not instantly: during a netsplit, both sides can briefly
  believe they own the same process, which is exactly the duplicate-work
  problem this module exists to prevent, just relocated to a rarer
  trigger instead of eliminated. Second, it would mean replacing the
  Registry/DynamicSupervisor pair already built and tested in Phase 2
  with Horde's equivalents, a much bigger change for a portfolio app
  that (for now) runs as a single Fly.io instance and has no near-term
  need to actually run multi-node.

  Postgres is already the one thing every node in this cluster
  necessarily agrees on (they all share one database), so asking it "who
  owns this lock" doesn't introduce a new source of truth, just reuses
  the existing one. A session-level advisory lock is released
  automatically the moment its holding connection closes — including a
  whole node crashing — so a dead node can never strand a monitor
  permanently un-owned.

  The tradeoff, made explicit: ownership doesn't rebalance. If node A
  wins the lock for monitor 7 at boot, node B will never run monitor 7's
  worker until node A's connection drops, even if A is far more loaded
  than B — there's no periodic re-shuffling. For this app's realistic
  scale (a handful of nodes, each easily able to run every monitor),
  that static, boot-time assignment is a reasonable trade for not
  needing a second clustering library.

  ## Why one connection per node, not one per monitor

  A session-level advisory lock is scoped to the *connection* that took
  it, not to any Elixir process — and a single connection can hold any
  number of distinct locks at once, each identified by its own bigint
  key (the monitor id). So one dedicated Postgrex connection, opened
  once when this GenServer starts and held for the node's lifetime, is
  enough no matter how many monitors this node ends up owning. This is
  a raw `Postgrex` connection, not one borrowed from `Pulsewatch.Repo`'s
  pool — a pooled connection could be handed back and reused for
  something else while "holding" a lock, which would silently break the
  one-owner-per-monitor guarantee this module exists to provide.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, [])
      name -> GenServer.start_link(__MODULE__, [], name: name)
    end
  end

  @doc """
  Tries to take this node's cluster-wide lock for `monitor_id`. Returns
  `true` if this node now owns it (immediately, whether or not it
  already did — the underlying lock is reentrant per connection), `false`
  if another node currently holds it.
  """
  @spec try_lock(integer(), GenServer.server()) :: boolean()
  def try_lock(monitor_id, server \\ __MODULE__) when is_integer(monitor_id) do
    GenServer.call(server, {:try_lock, monitor_id})
  end

  @doc "Releases this node's lock for `monitor_id`. A no-op if this node didn't hold it."
  @spec unlock(integer(), GenServer.server()) :: :ok
  def unlock(monitor_id, server \\ __MODULE__) when is_integer(monitor_id) do
    GenServer.call(server, {:unlock, monitor_id})
  end

  @impl true
  def init([]) do
    connection_opts =
      Pulsewatch.Repo.config()
      |> Keyword.take([:hostname, :port, :database, :username, :password, :socket_options, :ssl])

    Postgrex.start_link(connection_opts)
  end

  @impl true
  def handle_call({:try_lock, monitor_id}, _from, conn) do
    %Postgrex.Result{rows: [[locked?]]} =
      Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1)", [monitor_id])

    {:reply, locked?, conn}
  end

  def handle_call({:unlock, monitor_id}, _from, conn) do
    Postgrex.query!(conn, "SELECT pg_advisory_unlock($1)", [monitor_id])
    {:reply, :ok, conn}
  end
end
