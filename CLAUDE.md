# Pulsewatch — conventions

Website uptime monitor. Portfolio-quality Elixir/Phoenix app; hold every change
to these rules.

## Architecture

- **Business logic lives in contexts** (`Pulsewatch.Accounts`, `Pulsewatch.Monitoring`,
  `Pulsewatch.Alerts`, ...). Contexts are the only modules that touch `Repo`.
- **The web layer (controllers, LiveViews, channels) never calls `Repo` directly**
  and never builds `Ecto.Query`s itself — it calls context functions.
- OTP processes (GenServers, Oban workers) call context functions too; they
  don't reach into `Repo` or other processes' state directly.
- External services (HTTP checks, the LLM) are called through a `@behaviour`,
  with a real implementation and a `Mox`-based test double. Nothing in `lib/`
  hardcodes a concrete HTTP/LLM client — it takes the implementation from
  application config so tests can swap it.

## Function contracts

- Every public context function has `@doc` and `@spec`.
- Functions that can fail return `{:ok, result}` or `{:error, reason}` —
  never raise for expected failure modes (validation errors, not-found,
  external API failures). Reserve `!`-suffixed functions (`get_monitor!/1`)
  for the conventional Phoenix "raise if truly not there" cases, matching
  what `phx.gen` produces.
- No silently swallowed errors. A `rescue`/`catch` that discards the error
  without logging or returning it is a bug. If a failure is genuinely
  recoverable-and-uninteresting, say why in a comment.

## Testing

- Every feature ships with tests alongside it in the same phase/commit —
  not "add tests later."
- **Never call a real LLM (or any real external network service) in tests.**
  Everything network-bound goes through a behaviour + Mox; CI has no
  API keys and must never need one to pass.
- Prefer testing context functions directly over testing through LiveView
  where the logic under test isn't actually about the UI.

## Style

- Run `mix format` before committing.
- `mix credo --strict` and `mix dialyzer` must be clean before a phase is
  considered done.
