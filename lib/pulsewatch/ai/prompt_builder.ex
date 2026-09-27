defmodule Pulsewatch.Ai.PromptBuilder do
  @moduledoc """
  Builds the prompt asking an LLM for a short, plain-English incident
  summary. Deliberately a plain function with no I/O — the interesting
  logic (what to tell the model) is fully testable without a real or
  mocked LLM call.
  """

  alias Pulsewatch.Monitoring.{Check, Incident, Monitor}

  @doc "Builds the prompt for summarizing `incident`, given the checks recorded during it."
  @spec build(Monitor.t(), Incident.t(), [Check.t()]) :: String.t()
  def build(%Monitor{} = monitor, %Incident{} = incident, checks) when is_list(checks) do
    """
    You are writing a one-to-two sentence, plain-English summary of a website outage for a support dashboard. No markdown, no headings — just the sentence(s).

    Monitor: #{monitor.name} (#{monitor.url})
    Incident started: #{format_time(incident.started_at)}
    Incident resolved: #{format_time(incident.resolved_at)}

    Checks recorded during the incident, oldest first:
    #{Enum.map_join(checks, "\n", &format_check/1)}

    Summarize what likely happened — mention status codes, error messages, or a response-time trend if the data suggests one (e.g. rising response times before failure suggests overload; an instant connection refusal suggests the server process was down).
    """
  end

  defp format_check(%Check{} = check) do
    details =
      [
        check.status_code && "status #{check.status_code}",
        check.response_time_ms && "#{check.response_time_ms}ms",
        check.error_message && "error: #{check.error_message}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    "- #{format_time(check.checked_at)}: #{check.status}" <>
      if(details == "", do: "", else: " (#{details})")
  end

  defp format_time(nil), do: "unknown"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
end
