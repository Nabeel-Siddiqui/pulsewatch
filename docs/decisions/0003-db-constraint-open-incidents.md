# 3. A database constraint, not just application logic, for "one open incident per monitor"

## Status

Accepted (Phase 1).

## Context

A monitor should never have two simultaneously-open incidents. That
would mean two alert emails, two webhook POSTs, and two AI summaries
for what is, from the user's point of view, one outage. The application
already has a natural place to enforce this: `Checker` (or, from Phase 4
on, `Alerts`) checks whether an open incident exists before creating a
new one. The question is whether that check, alone, is enough.

## Decision

Enforce it in the database too, with a partial unique index,
`incidents_one_open_per_monitor`, on `incidents(monitor_id) WHERE
resolved_at IS NULL`. It doubles as the lookup index for the exact
question the checking engine asks on every failed check ("does this
monitor currently have an open incident?"), so it isn't purely a safety
net sitting unused. It's on the hot path.

## Consequences

- An application-level check-then-insert is a classic race condition
  once more than one process can reach it concurrently, which is exactly
  the situation from Phase 2 onward, where every monitor has its own
  independently-scheduled `MonitorWorker`. Two near-simultaneous failed
  checks for the same monitor (plausible if, say, a check is slow and
  the next one fires before the first finishes) could otherwise both see
  "no open incident" and both insert one. The database constraint makes
  that structurally impossible rather than merely unlikely: the loser of
  the race gets a constraint violation instead of a silently duplicated
  incident.
- This is also the seam `Alerts.open_incident/2` is built around
  (Phase 4). Losing the unique-index race and getting `{:error,
  changeset}` back is treated as an ordinary, expected outcome rather
  than an exception to rescue, so "another process already opened this
  incident" is just another branch of the `{:ok, _} | {:error, _}`
  contract every context function follows.
- The cost is one more migration to get right (the partial `WHERE`
  clause, specifically) and a constraint error that application code has
  to be written to expect and handle gracefully rather than treat as a
  should-never-happen bug. A small, worthwhile price for a guarantee
  that's otherwise only ever "probably true."
