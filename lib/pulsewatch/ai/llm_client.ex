defmodule Pulsewatch.Ai.LlmClient do
  @moduledoc """
  Behaviour for getting a plain-text completion from an LLM. Kept generic
  (one function, a prompt in, a string out) rather than Anthropic-specific
  — `Pulsewatch.Ai.PromptBuilder` owns what the prompt actually says.

  Three implementations: `AnthropicClient` (real, via Req), `DemoClient`
  (canned responses, so a deployment with no API key configured still
  produces plausible-looking summaries), and a Mox mock in tests.
  """

  @doc "Requests a completion for `prompt`. `{:error, reason}` for anything that isn't a usable response — the caller treats this as optional and never blocks on it."
  @callback complete(prompt :: String.t()) :: {:ok, String.t()} | {:error, reason :: term()}
end
