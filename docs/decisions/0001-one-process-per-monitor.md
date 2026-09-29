# 1. One OTP process per monitor

## Status

Accepted (Phase 2).

## Context

Something has to run each monitor's check on its own schedule, forever,
independently of every other monitor, and keep going after a crash. The
two realistic shapes for that in Elixir are: one long-lived GenServer
per monitor, self-scheduling with `Process.send_after/3`, or a single
central scheduler process that loops over every monitor and dispatches
checks (via `Task.Supervisor.async_nocatch`, a job queue, or similar).

## Decision

One `Pulsewatch.Monitoring.MonitorWorker` GenServer per active monitor,
registered in `Pulsewatch.Monitoring.Registry` by monitor id and
supervised by `Pulsewatch.Monitoring.MonitorSupervisor`, a
`DynamicSupervisor` with the default `:one_for_one` strategy. Each
worker schedules its own next check with jitter, so a fleet started
together (e.g. at boot) doesn't hit the network in lockstep. All
decision-making (when to mark a monitor down, when to open or resolve
an incident) lives in `Pulsewatch.Monitoring.Checker`, a plain,
process-free module the worker calls into. The GenServer is a thin
scheduling shell rather than where the logic lives, which is what keeps
`Checker`'s behavior unit-testable without a GenServer in the loop at
all.

## Consequences

- A crash in one monitor's check (a bad URL, an unexpected response
  shape, a bug) only takes down that one process. `:one_for_one` means
  the supervisor restarts it in isolation; every other monitor's worker
  is untouched and keeps checking on schedule. This is the main reason
  this shape was chosen over a central scheduler: a central process
  doing all N monitors' work has no equivalent fault boundary. A crash
  there risks every monitor at once, and even a caught, logged exception
  in one iteration risks a stuck bug taking down the whole loop's state.
- Supervision, not manual bookkeeping, gives start/stop/restart-by-id:
  `MonitorSupervisor.stop_worker/1` and `restart_worker/1` look the
  process up in the Registry by monitor id rather than requiring the
  caller to hold onto a pid.
- The cost is N processes for N monitors, each holding its own small
  bit of state (the monitor struct, a consecutive-failure counter) and
  its own pending timer. For the scale this app targets (an individual
  or small team's monitors, tens to low hundreds rather than tens of
  thousands), that's a non-issue on the BEAM. A scheduler design would
  only start winning at a scale where per-process memory overhead
  actually matters, which would be a good problem to revisit this
  decision over.
- Multi-node clustering (Phase 7) builds directly on this shape. Because
  ownership of a monitor is "does a MonitorWorker for this id exist,"
  cluster-wide exclusivity reduces to "does at most one node get to
  start that worker." See
  [4. Multi-node duplicate-worker prevention](0004-multi-node-duplicate-prevention.md).
