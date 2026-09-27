defmodule Pulsewatch.Alerts.WebhookClient.ReqClient do
  @moduledoc """
  Real `Pulsewatch.Alerts.WebhookClient` implementation, backed by `Req`.
  """

  @behaviour Pulsewatch.Alerts.WebhookClient

  @impl true
  def post(url, body) do
    case Req.post(url, json: body, receive_timeout: 10_000, retry: false) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        {:ok, status}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end
end
