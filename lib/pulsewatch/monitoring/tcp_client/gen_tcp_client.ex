defmodule Pulsewatch.Monitoring.TcpClient.GenTcpClient do
  @moduledoc """
  Real `Pulsewatch.Monitoring.TcpClient` implementation, backed by
  `:gen_tcp`. This is the only module in the app that actually opens a
  TCP socket for a monitor check.
  """

  @behaviour Pulsewatch.Monitoring.TcpClient

  @impl true
  def connect(host, port, timeout_ms) do
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], timeout_ms) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
