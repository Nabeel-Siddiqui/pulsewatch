defmodule Pulsewatch.Monitoring.Incident do
  @moduledoc """
  A period during which a monitor was down, from the first consecutive
  failure past the threshold until it recovered. `resolved_at` is nil
  while the incident is open; the database enforces at most one open
  incident per monitor (see the migration's partial unique index).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "incidents" do
    field :started_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :ai_summary, :string

    belongs_to :monitor, Pulsewatch.Monitoring.Monitor

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for opening a new incident."
  def open_changeset(incident, attrs) do
    incident
    |> cast(attrs, [:started_at])
    |> validate_required([:started_at])
    |> unique_constraint(:monitor_id, name: :incidents_one_open_per_monitor)
  end

  @doc "Changeset for resolving an open incident, optionally with an AI summary."
  def resolve_changeset(incident, attrs) do
    incident
    |> cast(attrs, [:resolved_at, :ai_summary])
    |> validate_required([:resolved_at])
  end

  @doc "Changeset for attaching an AI-generated summary after the fact — see Monitoring.update_incident_summary/2."
  def summary_changeset(incident, attrs) do
    incident
    |> cast(attrs, [:ai_summary])
    |> validate_required([:ai_summary])
  end
end
