# 7. TCP checks reuse the HTTP checker's behaviour seam, not a parallel code path

## Status

Accepted (TCP check support).

## Context

Every monitor so far made one HTTP GET and judged it on the status
code. A TCP port check (is Postgres listening on 5432, is the SSH
port open) is a genuinely different kind of check — there's no status
code, no response body, just "did a connection open or not" — but it's
the same *shape* of problem `Checker` already solved for HTTP:
perform one bounded-time network operation, time it, and turn the
result into `{status, elapsed, detail, error}`. The question was
whether that similarity was real enough to share code over, or
whether a TCP check deserved its own module and its own path through
`MonitorWorker`.

## Decision

`Monitor` gained a `check_type` field (`:http` | `:tcp`, `Ecto.Enum`)
and `Checker.run/2` dispatches on it via two `perform_request/1`
clauses, sharing everything downstream: the same `Check` record, the
same failure-threshold/incident logic, the same broadcast. TCP gets
its own behaviour, `Pulsewatch.Monitoring.TcpClient`
(`connect/3` — `:ok` or `{:error, reason}`, no status code to
report), with a real `:gen_tcp`-backed implementation and a `Mox`
double, mirroring `HttpClient` exactly. `Monitor.changeset/2` branches
the same way: an `:http` monitor requires `url`, a `:tcp` one requires
`host` and `port` — the other type's fields are simply ignored, not
cleared, since only the active `check_type` is ever read.

## Alternatives considered

- **A `TcpMonitorWorker` alongside `MonitorWorker`.** Would isolate TCP
  checks completely, but duplicates the scheduling, jitter,
  consecutive-failure counting, and incident logic that has nothing to
  do with *how* a check is performed — the actual HTTP-specific code
  was always just `perform_request/1`'s dozen lines, not the
  surrounding machinery.
- **One `url`-like field that's either an HTTP URL or a `host:port`
  string, sniffed at check time.** Avoids adding `host`/`port` columns,
  but pushes the "which kind of target is this" decision into string
  parsing instead of a field the database and the UI can both reason
  about directly, and loses the ability to validate a TCP target's
  port range at the changeset level.
- **Treat a TCP check as an HTTP check against a fake URL scheme**
  (`tcp://host:port`), reusing the existing `url` field and
  `HttpClient`. Rejected outright — `Req` (the real `HttpClient`
  implementation) speaks HTTP, not raw sockets; there's no honest way
  to make it "perform a TCP connect" without it secretly being a
  different client underneath anyway, which is the thing this
  alternative was trying to avoid writing.

## Consequences

- Adding a third check type (a TCP response-body assertion, or a raw
  ICMP ping) is "add a behaviour + a `perform_request/1` clause +
  a changeset branch," not "design a new worker from scratch" —
  the seam this ADR is named for is now proven out twice, not once.
- `expected_status_code` stays on every monitor row regardless of
  `check_type`, meaningless for TCP ones. A second nullable column
  wasn't worth it for a field that's simply never read on that path —
  the same reasoning `url`/`host`/`port` get for whichever type isn't
  active.
- The dashboard, the show page, and the JSON API all needed a
  `check_type`-aware "what's this monitor actually checking" display
  (`Monitor.target/1`) instead of printing `url` unconditionally —
  the one real piece of surface area this feature touched outside the
  checking engine itself.
