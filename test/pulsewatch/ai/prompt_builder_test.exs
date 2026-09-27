defmodule Pulsewatch.Ai.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias Pulsewatch.Ai.PromptBuilder
  alias Pulsewatch.Monitoring.{Check, Incident, Monitor}

  defp monitor(attrs \\ %{}) do
    struct(%Monitor{name: "API", url: "https://api.example.com"}, attrs)
  end

  defp incident(attrs \\ %{}) do
    struct(
      %Incident{
        started_at: ~U[2026-01-01 12:00:00.000000Z],
        resolved_at: ~U[2026-01-01 12:05:00.000000Z]
      },
      attrs
    )
  end

  defp check(attrs) do
    struct(%Check{checked_at: ~U[2026-01-01 12:01:00.000000Z]}, attrs)
  end

  test "includes the monitor's name and url" do
    prompt = PromptBuilder.build(monitor(), incident(), [])
    assert prompt =~ "API"
    assert prompt =~ "https://api.example.com"
  end

  test "includes each check's status, status code, response time, and error" do
    checks = [
      check(%{status: :down, status_code: 503, response_time_ms: 1200}),
      check(%{status: :down, error_message: "connection refused"}),
      check(%{status: :up, status_code: 200, response_time_ms: 80})
    ]

    prompt = PromptBuilder.build(monitor(), incident(), checks)

    assert prompt =~ "status 503"
    assert prompt =~ "1200ms"
    assert prompt =~ "connection refused"
    assert prompt =~ "status 200"
    assert prompt =~ "80ms"
  end

  test "an empty check list still produces a valid prompt (no crash)" do
    prompt = PromptBuilder.build(monitor(), incident(), [])
    assert is_binary(prompt)
    assert prompt =~ "API"
  end

  test "asks for plain English with no markdown" do
    prompt = PromptBuilder.build(monitor(), incident(), [])
    assert prompt =~ "No markdown"
  end
end
