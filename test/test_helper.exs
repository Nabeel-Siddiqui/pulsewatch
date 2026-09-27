ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Pulsewatch.Repo, :manual)

Mox.defmock(Pulsewatch.Monitoring.HttpClientMock, for: Pulsewatch.Monitoring.HttpClient)
