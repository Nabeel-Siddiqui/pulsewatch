# Populates the database with a demo user and a handful of sample
# monitors, so a fresh clone (or a public demo deployment) has something
# to look at immediately instead of an empty dashboard.
#
#     mix run priv/repo/seeds.exs
#
# Safe to run more than once: it looks the demo user up by email first
# and does nothing if they already exist, rather than erroring or
# creating duplicates.

alias Pulsewatch.Accounts
alias Pulsewatch.Monitoring.Engine
alias Pulsewatch.Repo

demo_email = "demo@pulsewatch.dev"

user =
  case Repo.get_by(Pulsewatch.Accounts.User, email: demo_email) do
    nil ->
      {:ok, user} =
        Accounts.register_user(%{
          email: demo_email,
          password: "demo-password-please-change"
        })

      user

    existing ->
      existing
  end

sample_monitors = [
  %{name: "Pulsewatch marketing site", url: "https://example.com", check_interval_seconds: 60},
  %{
    name: "Pulsewatch API",
    url: "https://api.example.com/health",
    check_interval_seconds: 30,
    expected_status_code: 200
  },
  %{
    name: "Status page",
    url: "https://status.example.com",
    check_interval_seconds: 300
  }
]

for attrs <- sample_monitors do
  unless Repo.get_by(Pulsewatch.Monitoring.Monitor, user_id: user.id, name: attrs.name) do
    {:ok, _monitor} = Engine.create_monitor(user, attrs)
  end
end

IO.puts("""

Seeded demo user:
  email:    #{demo_email}
  password: demo-password-please-change

#{length(sample_monitors)} sample monitor(s) created (or already present).
""")
