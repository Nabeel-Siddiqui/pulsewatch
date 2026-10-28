defmodule Pulsewatch.Repo.Migrations.AddTcpCheckSupport do
  use Ecto.Migration

  # url has to become nullable: a TCP monitor has a host/port instead,
  # not a URL. expected_status_code keeps its NOT NULL + default —
  # meaningless for a TCP check, but harmless to leave set, and not
  # worth a second nullable column just for that.
  def change do
    alter table(:monitors) do
      add :check_type, :string, null: false, default: "http"
      add :host, :string
      add :port, :integer
    end

    execute "ALTER TABLE monitors ALTER COLUMN url DROP NOT NULL",
            "ALTER TABLE monitors ALTER COLUMN url SET NOT NULL"
  end
end
