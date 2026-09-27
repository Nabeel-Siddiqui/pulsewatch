defmodule Pulsewatch.Ai.LlmClient.DemoClientTest do
  use ExUnit.Case, async: true

  alias Pulsewatch.Ai.LlmClient.DemoClient

  test "always returns {:ok, summary} regardless of the prompt" do
    assert {:ok, summary} = DemoClient.complete("anything at all")
    assert is_binary(summary)
    assert String.length(summary) > 0
  end

  test "returns more than one distinct canned response across calls" do
    summaries =
      for _ <- 1..50 do
        {:ok, summary} = DemoClient.complete("x")
        summary
      end

    # Not asserting exact randomness distribution — just that this isn't
    # hardcoded to a single string, which would look identical on every
    # demo incident and give the game away immediately.
    assert summaries |> Enum.uniq() |> length() > 1
  end
end
