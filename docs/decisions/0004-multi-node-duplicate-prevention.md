# 4. Postgres advisory locks for multi-node duplicate-worker prevention, not Horde

## Status

Accepted (Phase 7).

## Context

`dns_cluster` connects every node running this app into one Erlang
cluster automatically, using each platform's own service discovery
(e.g. Fly.io's internal DNS). But `Pulsewatch.Monitoring.Registry` and
`MonitorSupervisor` (see
[1. One process per monitor](0001-one-process-per-monitor.md)) are both
local to a node — clustering the nodes doesn't, by itself, stop each one
from independently starting a worker for every active monitor. Scale
this app to two machines with nothing else changed and every monitor
gets checked twice per interval, and every incident gets alerted on
twice. Something has to make "which node owns this monitor" cluster-wide
information instead of per-node.

Two realistic answers: **Horde**, a CRDT-backed distributed
Registry/DynamicSupervisor built for exactly this class of problem, or
**Postgres advisory locks** (`pg_try_advisory_lock`/
`pg_advisory_unlock`), using the database every node already shares as
the source of truth for ownership.

## Decision

Postgres advisory locks, via a new `Pulsewatch.Monitoring.NodeLock`
GenServer: one dedicated Postgrex connection per node (not borrowed from
the `Repo` pool, since a pooled connection could be handed to something
else while "holding" a lock), used to claim a session-level advisory
lock per monitor id before `MonitorSupervisor.start_worker/1` starts a
worker, and to release it in `stop_worker/1`.

Horde was seriously considered and rejected for two concrete reasons,
not just "it's more moving parts":

1. Horde's CRDT registry converges *eventually*, not instantly. During a
   network partition, both sides of the split can briefly believe they
   own the same process — which is the exact duplicate-ownership problem
   this decision exists to prevent, just relocated from "every day, by
   design" to "rarely, during a partition." Advisory locks don't have
   this failure mode: Postgres is a single authority, not two
   independently-progressing replicas that need to reconcile.
2. Adopting Horde means replacing the Registry/DynamicSupervisor pair
   built and tested in Phase 2 with Horde's equivalents — a much larger
   change than adding one new GenServer alongside the existing
   supervision tree.

## Consequences

- Ownership is **static, not rebalanced**. If node A wins the lock for
  monitor 7 at boot, node B will never take over running monitor 7's
  worker until A's connection drops — even if A is far more loaded than
  B. There is no periodic reshuffling. This is the tradeoff being made
  explicitly: for this app's realistic scale (a handful of nodes, each
  easily capable of running every monitor), static assignment is an
  acceptable price for not needing a second clustering library. It would
  stop being acceptable at a scale where load genuinely needs to
  rebalance across nodes — at that point, revisiting Horde (or a
  purpose-built work-distribution system) would be the right call.
- A session-level advisory lock releases automatically the instant its
  holding connection closes, including a full node crash — so a dead
  node can never strand a monitor permanently unowned. This is a direct
  benefit of piggybacking on a mechanism Postgres already implements
  correctly, rather than one this app would have to get right itself
  (e.g. a lease with a TTL and a renewal loop).
- One connection is required per node regardless of how many monitors it
  ends up owning, since a single Postgres session can hold any number of
  distinct advisory locks simultaneously (each keyed by its own bigint —
  the monitor id). This is why `NodeLock` is one GenServer per node, not
  one per monitor.
- A known, accepted gap: two truly concurrent `start_worker/1` calls for
  the *same* monitor on the *same* node (not a realistic scenario in
  today's call sites, which are boot-time and single-user CRUD actions)
  can each acquire the reentrant lock before either starts its child,
  leaving the lock's internal hold-count above what a single
  `stop_worker/1` call later releases. Not fixed here — noted as a
  narrow, low-probability edge case rather than engineering a fully
  serialized claim-and-start path for a race that doesn't occur under
  this app's actual usage.
