defmodule Pulsewatch.Ai.LlmClient.DemoClient do
  @moduledoc """
  Fake `Pulsewatch.Ai.LlmClient` that returns a plausible-sounding, canned
  incident summary instead of calling a real model. Used automatically
  whenever `ANTHROPIC_API_KEY` isn't set (see `config/runtime.exs`), so a
  fresh clone — or a public demo deployment — shows working AI summaries
  without needing anyone to bring their own API key.
  """

  @behaviour Pulsewatch.Ai.LlmClient

  @responses [
    "The site returned repeated timeouts before recovering; response times had been climbing for several checks beforehand, consistent with the server becoming overloaded.",
    "Requests started failing with 503 errors; the outage lasted a few minutes before the service came back cleanly with no further errors.",
    "Connection attempts were refused for the duration of the incident, suggesting the server process itself was down rather than just slow to respond.",
    "The monitor saw a mix of 500 errors and timeouts, with response times elevated in the checks immediately preceding the failures — likely a resource exhaustion issue that resolved on its own.",
    "A single unexpected status code triggered the incident and it resolved on the very next check, suggesting a brief, transient blip rather than a sustained outage."
  ]

  @impl true
  def complete(_prompt) do
    {:ok, Enum.random(@responses)}
  end
end
