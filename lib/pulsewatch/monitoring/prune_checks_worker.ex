defmodule Pulsewatch.Monitoring.PruneChecksWorker do
  @moduledoc """
  Nightly cron job (see the `Oban.Plugins.Cron` entry in config) that
  deletes checks older than 30 days. Check volume grows without bound
  otherwise — one row per monitor per check interval, forever.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  alias Pulsewatch.Monitoring

  @retention_days 30

  @impl Oban.Worker
  def perform(_job) do
    count = Monitoring.delete_checks_older_than(@retention_days)
    Logger.info("pruned old checks", count: count, retention_days: @retention_days)
    :ok
  end
end
