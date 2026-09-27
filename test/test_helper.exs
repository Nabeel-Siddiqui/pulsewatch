ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Pulsewatch.Repo, :manual)

Mox.defmock(Pulsewatch.Monitoring.HttpClientMock, for: Pulsewatch.Monitoring.HttpClient)
Mox.defmock(Pulsewatch.Alerts.WebhookClientMock, for: Pulsewatch.Alerts.WebhookClient)
Mox.defmock(Pulsewatch.Ai.LlmClientMock, for: Pulsewatch.Ai.LlmClient)
