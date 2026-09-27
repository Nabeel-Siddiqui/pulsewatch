defmodule PulsewatchWeb.Plugs.RateLimit do
  @moduledoc """
  Rate-limits JSON API requests per token (not per account — two tokens
  for the same user get independent budgets), via `Hammer`. Must run
  after `PulsewatchWeb.Plugs.ApiAuth`, which is what assigns
  `:current_api_token`.

  Limit and window are configurable (`config :pulsewatch, :api_rate_limit`)
  so tests can use a tiny window instead of actually sending 60 requests.

  Fails open on a limiter backend error — an ETS bucket read/write is
  vanishingly unlikely to fail on a single node, and blocking all API
  traffic because the rate limiter itself is unhealthy would be a worse
  outcome than occasionally under-enforcing a limit.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  require Logger

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{assigns: %{current_api_token: token}} = conn, _opts) do
    {limit, scale_ms} = config()

    case Hammer.check_rate("api_token:#{token.id}", scale_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(div(scale_ms, 1000)))
        |> put_status(:too_many_requests)
        |> json(%{errors: %{detail: "rate limit exceeded, try again later"}})
        |> halt()

      {:error, reason} ->
        Logger.warning("rate limiter backend error, allowing request", reason: inspect(reason))
        conn
    end
  end

  defp config do
    defaults = [limit: 60, scale_ms: 60_000]
    config = Application.get_env(:pulsewatch, :api_rate_limit, defaults)
    {Keyword.fetch!(config, :limit), Keyword.fetch!(config, :scale_ms)}
  end
end
