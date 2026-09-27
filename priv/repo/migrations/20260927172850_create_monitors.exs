defmodule Pulsewatch.Repo.Migrations.CreateMonitors do
  use Ecto.Migration

  def change do
    create table(:monitors) do
      add :name, :string, null: false
      add :url, :string, null: false
      add :check_interval_seconds, :integer, null: false, default: 60
      add :expected_status_code, :integer, null: false, default: 200
      add :timeout_ms, :integer, null: false, default: 5_000
      add :active, :boolean, null: false, default: true
      add :webhook_url, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:monitors, [:user_id])
  end
end
