defmodule Pulsewatch.Monitoring.HttpClient.ReqClient do
  @moduledoc """
  Real `Pulsewatch.Monitoring.HttpClient` implementation, backed by `Req`.
  This is the only module in the app that actually makes a network call
  for a monitor check.
  """

  @behaviour Pulsewatch.Monitoring.HttpClient

  @impl true
  def get(url, timeout_ms) do
    case Req.get(url,
           receive_timeout: timeout_ms,
           connect_options: [timeout: timeout_ms],
           retry: false
         ) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, exception} -> {:error, exception}
    end
  end
end
