# 2. Oban for alerts and AI summaries, not plain Tasks

## Status

Accepted (Phase 4).

## Context

Two kinds of work need to happen *after* an incident opens or resolves,
off the request/check path: sending an alert (email + optional webhook)
and, on resolve, asking an LLM for a plain-English summary. Both can
fail transiently (a webhook endpoint down, an SMTP hiccup, an LLM
provider's 429) and both need to survive the BEAM node restarting
without silently vanishing. `Task.Supervisor.start_child/2` (or plain
`spawn`) is the zero-dependency way to do background work in Elixir;
`Oban` is a Postgres-backed job queue with retries, backoff, and
persistence built in.

## Decision

Use Oban. `IncidentAlertWorker` and `IncidentSummaryWorker` are both
`Oban.Worker`s, enqueued via `Oban.insert/3` composed directly into the
*same* `Ecto.Multi` that records the incident's open/resolve — see
[3. Database constraint for one open incident per monitor](0003-db-constraint-open-incidents.md)
for why that matters. Idempotency comes from Oban's `unique:` option
(keyed on `incident_id` + event for alerts, so the same incident
transition can never enqueue two alert jobs), and retry/backoff is
built in rather than hand-rolled (`max_attempts: 5` on the webhook
delivery). A nightly cron job (`Oban.Plugins.Cron`) prunes old checks —
see [6. Data retention](0006-data-retention.md) — which needs a
persistent, restart-surviving schedule, not something an in-memory
`Task` could give for free either.

## Consequences

- A `Task` spawned right after inserting the incident is not in the
  same transaction as that insert — if the process crashes, the node
  restarts, or the task itself just fails, the alert silently never
  goes out, with nothing to notice or retry it. Composing the job
  insert into the incident's own `Ecto.Multi` makes "an incident is
  recorded" and "its alert job is queued" atomic: either both happen or
  neither does, enforced by Postgres, not by hoping a spawned process
  runs to completion.
- Retries with backoff, a max-attempts cap, and persistence across
  restarts all come from Oban directly — reimplementing even a basic
  version of this over bare `Task`s (a retry loop, backoff, and some
  way to survive a node restart without a durable job table) would be
  reinventing a worse version of what Oban already does well.
- The cost is a real dependency and a job table living in the same
  Postgres database as the app's own data — one more piece of
  infrastructure to reason about (queues, plugins, migrations for
  `oban_jobs`), and one more thing that could theoretically fail
  (though it degrades gracefully: a Postgres outage means jobs don't
  enqueue, not that anything corrupts). For an app this size that
  tradeoff is clearly worth it, given how much of "reliable background
  work" it buys for one dependency.
