defmodule Pulsewatch.Monitoring.CheckerTest do
  use Pulsewatch.DataCase, async: true

  import Mox
  import Pulsewatch.MonitoringFixtures

  alias Pulsewatch.Monitoring
  alias Pulsewatch.Monitoring.Checker

  setup :verify_on_exit!

  describe "run/2 — success" do
    test "records an :up check and stays at 0 failures" do
      monitor = monitor_fixture(%{expected_status_code: 200})
      expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:ok, 200} end)

      assert %{check: check, consecutive_failures: 0, transition: :no_change} =
               Checker.run(monitor, 0)

      assert check.status == :up
      assert check.status_code == 200
      assert check.error_message == nil
    end

    test "an unexpected status code counts as a failure, not a success" do
      monitor = monitor_fixture(%{expected_status_code: 200})
      expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:ok, 503} end)

      assert %{check: check, consecutive_failures: 1, transition: :no_change} =
               Checker.run(monitor, 0)

      assert check.status == :down
      assert check.status_code == 503
      assert check.error_message =~ "503"
    end

    test "recovering from down (>= threshold failures) resolves the open incident" do
      monitor = monitor_fixture()
      {:ok, _incident} = Monitoring.open_incident(monitor)
      expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:ok, 200} end)

      assert %{consecutive_failures: 0, transition: :became_up} = Checker.run(monitor, 2)

      assert {:error, :not_found} = Monitoring.get_open_incident(monitor)
    end

    test "a success with no prior failures has nothing to resolve" do
      monitor = monitor_fixture()
      expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:ok, 200} end)

      assert %{transition: :no_change} = Checker.run(monitor, 0)
    end
  end

  describe "run/2 — failure" do
    test "a single failure does not open an incident (below threshold)" do
      monitor = monitor_fixture()

      expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout ->
        {:error, :timeout}
      end)

      assert %{consecutive_failures: 1, transition: :no_change} = Checker.run(monitor, 0)
      assert {:error, :not_found} = Monitoring.get_open_incident(monitor)
    end

    test "the 2nd consecutive failure crosses the threshold and opens an incident" do
      monitor = monitor_fixture()

      expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout ->
        {:error, :timeout}
      end)

      assert %{consecutive_failures: 2, transition: :became_down} = Checker.run(monitor, 1)
      assert {:ok, _incident} = Monitoring.get_open_incident(monitor)
    end

    test "a 3rd+ consecutive failure stays down without opening a second incident" do
      monitor = monitor_fixture()
      {:ok, incident} = Monitoring.open_incident(monitor)

      expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout ->
        {:error, :timeout}
      end)

      assert %{consecutive_failures: 3, transition: :no_change} = Checker.run(monitor, 2)

      assert {:ok, still_open} = Monitoring.get_open_incident(monitor)
      assert still_open.id == incident.id
    end

    test "a transport error records status_code: nil and a readable error_message" do
      monitor = monitor_fixture()

      expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout ->
        {:error, %Mint.TransportError{reason: :timeout}}
      end)

      assert %{check: check} = Checker.run(monitor, 0)
      assert check.status_code == nil
      assert check.error_message =~ "timeout"
    end
  end

  describe "run/2 — tcp checks" do
    test "a successful connection records an :up check with no status code" do
      monitor = monitor_fixture(%{check_type: :tcp, host: "db.example.com", port: 5432, url: nil})
      expect(Pulsewatch.Monitoring.TcpClientMock, :connect, fn _host, _port, _timeout -> :ok end)

      assert %{check: check, consecutive_failures: 0, transition: :no_change} =
               Checker.run(monitor, 0)

      assert check.status == :up
      assert check.status_code == nil
      assert check.error_message == nil
    end

    test "a connection refusal counts as a failure with a readable error_message" do
      monitor = monitor_fixture(%{check_type: :tcp, host: "db.example.com", port: 5432, url: nil})

      expect(Pulsewatch.Monitoring.TcpClientMock, :connect, fn _host, _port, _timeout ->
        {:error, :econnrefused}
      end)

      assert %{check: check, consecutive_failures: 1, transition: :no_change} =
               Checker.run(monitor, 0)

      assert check.status == :down
      assert check.status_code == nil
      assert check.error_message =~ "econnrefused"
    end

    test "a tcp monitor crossing the failure threshold opens an incident, same as http" do
      monitor = monitor_fixture(%{check_type: :tcp, host: "db.example.com", port: 5432, url: nil})

      expect(Pulsewatch.Monitoring.TcpClientMock, :connect, fn _host, _port, _timeout ->
        {:error, :timeout}
      end)

      assert %{transition: :became_down} = Checker.run(monitor, 1)
      assert {:ok, _incident} = Monitoring.get_open_incident(monitor)
    end

    test "never calls the http client for a tcp monitor, and vice versa" do
      tcp_monitor =
        monitor_fixture(%{check_type: :tcp, host: "db.example.com", port: 5432, url: nil})

      expect(Pulsewatch.Monitoring.TcpClientMock, :connect, fn _host, _port, _timeout -> :ok end)
      # No HttpClientMock expectation set — Mox raises if it's called unexpectedly.
      Checker.run(tcp_monitor, 0)

      http_monitor = monitor_fixture(%{check_type: :http})
      expect(Pulsewatch.Monitoring.HttpClientMock, :get, fn _url, _timeout -> {:ok, 200} end)
      # No TcpClientMock expectation set here either.
      Checker.run(http_monitor, 0)
    end
  end
end
