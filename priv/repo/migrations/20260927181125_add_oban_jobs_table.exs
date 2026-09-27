defmodule Pulsewatch.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up, do: Oban.Migrations.up()

  # Oban migrations are versioned and additive; down/0 rolls back every
  # version this app has ever run, all the way to nothing.
  def down, do: Oban.Migrations.down(version: 1)
end
