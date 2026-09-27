defmodule Pulsewatch.Repo.Migrations.CreateIncidents do
  use Ecto.Migration

  def change do
    create table(:incidents) do
      add :started_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :ai_summary, :text
      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:incidents, [:monitor_id])

    # A monitor can have at most one open (unresolved) incident at a time.
    # This is enforced by the database, not just application logic — a
    # partial unique index on rows where resolved_at IS NULL. It doubles as
    # the lookup index for "does this monitor currently have an open
    # incident?", which the checking engine asks on every failed check.
    create unique_index(:incidents, [:monitor_id],
             where: "resolved_at IS NULL",
             name: :incidents_one_open_per_monitor
           )
  end
end
