defmodule Pulsewatch.Repo.Migrations.CreateChecks do
  use Ecto.Migration

  def change do
    create table(:checks) do
      add :status, :string, null: false
      add :response_time_ms, :integer
      add :status_code, :integer
      add :error_message, :string
      add :checked_at, :utc_datetime_usec, null: false
      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false
    end

    # Checks are immutable, append-only events — no updated_at. The common
    # query is "the last N checks for this monitor, newest first", which
    # this composite index serves directly (Postgres scans a btree
    # efficiently in either direction, so no separate DESC index is needed).
    create index(:checks, [:monitor_id, :checked_at])
  end
end
