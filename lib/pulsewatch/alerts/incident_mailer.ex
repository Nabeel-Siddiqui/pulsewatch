defmodule Pulsewatch.Alerts.IncidentMailer do
  @moduledoc """
  Composes and delivers the "your monitor went down / recovered" email.
  Delivery goes through `Pulsewatch.Mailer`, which uses the Local adapter
  in dev (see /dev/mailbox) and the Test adapter in test — nothing in
  the suite ever sends a real email.
  """

  import Swoosh.Email

  alias Pulsewatch.Accounts.User
  alias Pulsewatch.Mailer
  alias Pulsewatch.Monitoring.{Incident, Monitor}

  @from {"Pulsewatch", "alerts@pulsewatch.local"}

  @doc """
  Builds and delivers the incident-opened or incident-resolved email to
  the monitor's owner. `event` is a plain string ("opened"/"resolved"),
  not an atom — it comes from an Oban job's args, which are always JSON
  (and therefore always strings) once round-tripped through the database,
  so there's no value in converting it back to an atom just to convert it
  again on the way in.
  """
  @spec deliver_incident_email(User.t(), Monitor.t(), Incident.t(), String.t()) ::
          {:ok, term()} | {:error, term()}
  def deliver_incident_email(%User{} = user, %Monitor{} = monitor, %Incident{} = incident, event)
      when event in ["opened", "resolved"] do
    user.email
    |> build_email(monitor, incident, event)
    |> Mailer.deliver()
  end

  defp build_email(to_email, monitor, incident, "opened") do
    new()
    |> to(to_email)
    |> from(@from)
    |> subject("🔴 #{monitor.name} is down")
    |> text_body("""
    #{monitor.name} (#{monitor.url}) stopped responding as expected at #{format(incident.started_at)}.

    You'll get another email when it recovers.
    """)
  end

  defp build_email(to_email, monitor, incident, "resolved") do
    new()
    |> to(to_email)
    |> from(@from)
    |> subject("✅ #{monitor.name} recovered")
    |> text_body("""
    #{monitor.name} (#{monitor.url}) recovered at #{format(incident.resolved_at)}.

    It was down for #{duration(incident)}.
    #{if incident.ai_summary, do: "\nSummary: " <> incident.ai_summary, else: ""}
    """)
  end

  defp format(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  defp duration(%Incident{started_at: started_at, resolved_at: resolved_at}) do
    seconds = DateTime.diff(resolved_at, started_at)
    "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  end
end
