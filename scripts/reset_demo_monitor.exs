# Used by scripts/record_demo (via `mix run`), not meant to be run by
# hand. Resets the "Payments webhook" demo monitor to a fresh, never-
# checked state so the GIF recording gets a real Up -> Down -> incident-
# opened transition on screen every time the script reruns, instead of
# replaying a monitor that's already been down for hours.
#
# Its check_interval_seconds (3s) is below the 30s floor the UI form
# enforces — this monitor is only ever created here, via Repo.insert!
# bypassing that changeset validation, specifically so two checks (and
# the incident they open) happen inside a ~15s recording instead of a
# ~65s one. Nothing about the normal create path (Engine.create_monitor,
# the UI form) changes.

alias Pulsewatch.Accounts.User
alias Pulsewatch.Monitoring.Monitor
alias Pulsewatch.Repo

user = Repo.get_by!(User, email: "demo@pulsewatch.dev")

if existing = Repo.get_by(Monitor, user_id: user.id, name: "Payments webhook") do
  Repo.delete!(existing)
end

{:ok, monitor} =
  Repo.insert(%Monitor{
    user_id: user.id,
    name: "Payments webhook",
    url: "https://payments.pulsewatch-demo.invalid/health",
    check_interval_seconds: 3,
    expected_status_code: 200,
    timeout_ms: 1_000,
    active: true
  })

IO.puts("demo monitor id: #{monitor.id}")
