# 6. 30-day check retention, pruned nightly

## Status

Accepted (Phase 4).

## Context

`checks` is an append-only, immutable log — one row per monitor per
check interval, forever, with no updates. At a 30-second interval (the
minimum this app allows), a single monitor generates roughly 2,880 rows
a day. Left completely unpruned, this table grows without bound for as
long as a monitor exists, most of it data nobody will ever look at again
— the dashboard shows current status and a 24-hour uptime percentage,
and the response-time chart is windowed to 24 hours.

## Decision

`PruneChecksWorker`, an Oban job scheduled nightly at 03:00 UTC via
`Oban.Plugins.Cron`, deletes `checks` rows older than 30 days.
Thirty days is chosen to comfortably outlive every feature that actually
reads check history — the 24-hour dashboard window, and the "checks
during this incident's window" query the AI summary worker uses, which
only ever looks back as far as the incident itself — while still leaving
enough history to answer "how has this monitor's reliability trended
over the last month" if someone wants to eyeball it directly.

## Consequences

- Table growth is bounded: at steady state, a monitor holds at most
  ~30 days of checks regardless of how long it's existed, so query
  performance and storage cost don't quietly degrade over the app's
  lifetime the way an unpruned append-only log eventually would.
- This is a hidden, unannounced deletion from the end user's point of
  view — there is no separate "export your check history first" flow.
  For a portfolio/demo-scale app that's an acceptable simplification;
  a product with real customers relying on longer-window historical
  reporting would need either a longer retention window, a cheaper cold
  archive tier (e.g. rolling checks up into daily aggregates before
  deleting the raw rows), or an explicit export feature before deleting
  anything.
- Incidents and their AI summaries are *not* pruned — only the raw
  `checks` log is. An incident's own record (start/resolve time, the
  eventual summary) is small, low-volume, and arguably the more
  valuable long-term artifact (it's already the plain-English account of
  what happened), so keeping incidents indefinitely while pruning their
  much higher-volume supporting check data is a deliberate, asymmetric
  choice, not an oversight.
