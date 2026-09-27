defmodule Pulsewatch.Monitoring.HttpClient do
  @moduledoc """
  Behaviour for performing the single HTTP request a monitor check needs.

  Kept deliberately narrow (one function, plain return values) so the real
  network-touching implementation can sit behind a `Mox` mock in tests —
  nothing in the checking engine ever makes a real HTTP request in the test
  suite. The configured implementation is looked up at call time via
  `config :pulsewatch, :http_client`, not compile time, so `Mox` can swap
  it per-test.
  """

  @doc """
  Performs a GET request against `url`, aborting after `timeout_ms`.

  Returns `{:ok, status_code}` for any response the server sent (including
  4xx/5xx — that's a valid HTTP response, just possibly not the one the
  monitor expects) or `{:error, reason}` if the request never got a
  response at all (timeout, DNS failure, connection refused, ...).
  """
  @callback get(url :: String.t(), timeout_ms :: pos_integer()) ::
              {:ok, status_code :: pos_integer()} | {:error, reason :: term()}
end
