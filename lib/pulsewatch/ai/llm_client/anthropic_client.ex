defmodule Pulsewatch.Ai.LlmClient.AnthropicClient do
  @moduledoc """
  Real `Pulsewatch.Ai.LlmClient` implementation: the Anthropic Messages
  API via `Req`. Model and API key are both configurable
  (`:pulsewatch, :llm_model` / `:anthropic_api_key`, set from
  `ANTHROPIC_MODEL` / `ANTHROPIC_API_KEY` in `config/runtime.exs`).
  """

  @behaviour Pulsewatch.Ai.LlmClient

  @api_url "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"
  @default_model "claude-haiku-4-5-20251001"

  @impl true
  def complete(prompt) do
    req =
      Req.new(
        url: @api_url,
        headers: [
          {"x-api-key", api_key()},
          {"anthropic-version", @anthropic_version}
        ],
        json: %{
          "model" => model(),
          "max_tokens" => 300,
          "messages" => [%{"role" => "user", "content" => prompt}]
        },
        receive_timeout: 20_000,
        # Retries connection errors, timeouts, 429s, and 5xxs with backoff.
        retry: :transient,
        max_retries: 2
      )

    case Req.post(req) do
      {:ok, %Req.Response{status: 200, body: body}} -> extract_text(body)
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp extract_text(%{"content" => [%{"text" => text} | _rest]}) when is_binary(text) do
    {:ok, String.trim(text)}
  end

  defp extract_text(body), do: {:error, {:unexpected_response, body}}

  defp model, do: Application.get_env(:pulsewatch, :llm_model, @default_model)
  defp api_key, do: Application.fetch_env!(:pulsewatch, :anthropic_api_key)
end
