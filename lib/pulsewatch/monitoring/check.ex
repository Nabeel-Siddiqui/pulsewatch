defmodule Pulsewatch.Monitoring.Check do
  @moduledoc """
  One immutable, point-in-time check result for a monitor. Append-only:
  checks are never updated after being written, only pruned once they age
  out (see the retention Oban job in a later phase).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(up down)a

  schema "checks" do
    field :status, Ecto.Enum, values: @statuses
    field :response_time_ms, :integer
    field :status_code, :integer
    field :error_message, :string
    field :checked_at, :utc_datetime_usec

    belongs_to :monitor, Pulsewatch.Monitoring.Monitor
  end

  @doc false
  def changeset(check, attrs) do
    check
    |> cast(attrs, [:status, :response_time_ms, :status_code, :error_message, :checked_at])
    |> validate_required([:status, :checked_at])
    |> validate_number(:response_time_ms, greater_than_or_equal_to: 0)
  end
end
