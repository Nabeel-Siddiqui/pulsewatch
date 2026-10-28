defmodule Pulsewatch.Monitoring.TcpClient do
  @moduledoc """
  Behaviour for the single TCP connection attempt a port-check monitor
  needs. The same seam `HttpClient` uses for the HTTP case: a real
  implementation backed by `:gen_tcp`, and a `Mox`-based test double so
  nothing in the test suite opens a real socket.
  """

  @doc """
  Attempts to open a TCP connection to `host`:`port`, aborting after
  `timeout_ms`. Successfully connecting is the entire signal — there's
  no response body or status to inspect, unlike an HTTP check — so the
  connection is closed immediately once it's confirmed open.

  Returns `:ok` for a successful connection or `{:error, reason}` if
  one couldn't be made at all (timeout, connection refused, unknown
  host, ...).
  """
  @callback connect(host :: String.t(), port :: :inet.port_number(), timeout_ms :: pos_integer()) ::
              :ok | {:error, reason :: term()}
end
