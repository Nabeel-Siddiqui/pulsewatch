defmodule Pulsewatch.Alerts.WebhookClient do
  @moduledoc """
  Behaviour for POSTing an incident alert payload to a monitor's
  configured webhook URL. Same shape as `Pulsewatch.Monitoring.HttpClient`
  (real Req-backed implementation + Mox mock in tests) but a distinct
  behaviour — this is a POST with a JSON body and a different success
  contract, not another monitor-check GET.
  """

  @doc "POSTs `body` (JSON-encoded) to `url`. `{:ok, status}` for any HTTP response, `{:error, reason}` if the request never completed."
  @callback post(url :: String.t(), body :: map()) ::
              {:ok, status_code :: pos_integer()} | {:error, reason :: term()}
end
