defmodule Pulsewatch.Config do
  @moduledoc """
  One place for the "which implementation does this behaviour use"
  lookup repeated across `Checker`, `IncidentAlertWorker`, and
  `IncidentSummaryWorker` — each resolves its HTTP/webhook/LLM client
  the same way: an app-config override (set in test/demo config) if
  present, a real implementation otherwise.
  """

  @doc "Resolves the module configured under `:pulsewatch, key`, or `default` if unset."
  @spec impl(atom(), module()) :: module()
  def impl(key, default) when is_atom(key) and is_atom(default) do
    Application.get_env(:pulsewatch, key, default)
  end
end
