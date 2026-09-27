defmodule Pulsewatch.Monitoring do
  @moduledoc """
  The Monitoring context: monitors, their check history, and incidents.

  Every monitor read/write that's reachable from the web layer takes the
  acting `%User{}` and is scoped to that user's own monitors — a monitor
  belonging to someone else is treated as not found, not merely
  unauthorized, so we never leak whether a given id exists.
  """

  import Ecto.Query, warn: false

  alias Pulsewatch.Accounts.User
  alias Pulsewatch.Monitoring.{Check, Incident, Monitor}
  alias Pulsewatch.Repo

  ## Monitors

  @doc "Lists a user's monitors, alphabetically by name."
  @spec list_monitors(User.t()) :: [Monitor.t()]
  def list_monitors(%User{} = user) do
    Monitor
    |> scope_to_user(user)
    |> order_by([m], asc: m.name)
    |> Repo.all()
  end

  @doc "Fetches one of a user's monitors by id."
  @spec get_monitor(User.t(), term()) :: {:ok, Monitor.t()} | {:error, :not_found}
  def get_monitor(%User{} = user, id) do
    Monitor
    |> scope_to_user(user)
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      monitor -> {:ok, monitor}
    end
  end

  @doc """
  Fetches one of a user's monitors by id, raising if it doesn't exist (or
  isn't theirs).
  """
  @spec get_monitor!(User.t(), term()) :: Monitor.t()
  def get_monitor!(%User{} = user, id) do
    Monitor
    |> scope_to_user(user)
    |> Repo.get!(id)
  end

  @doc "Creates a monitor owned by `user`."
  @spec create_monitor(User.t(), map()) :: {:ok, Monitor.t()} | {:error, Ecto.Changeset.t()}
  def create_monitor(%User{} = user, attrs) do
    %Monitor{user_id: user.id}
    |> Monitor.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a monitor. `user` must own it."
  @spec update_monitor(User.t(), Monitor.t(), map()) ::
          {:ok, Monitor.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_monitor(%User{} = user, %Monitor{} = monitor, attrs) do
    with :ok <- authorize(user, monitor) do
      monitor
      |> Monitor.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc "Deletes a monitor. `user` must own it."
  @spec delete_monitor(User.t(), Monitor.t()) ::
          {:ok, Monitor.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def delete_monitor(%User{} = user, %Monitor{} = monitor) do
    with :ok <- authorize(user, monitor) do
      Repo.delete(monitor)
    end
  end

  @doc "Pauses a monitor (sets `active: false`). `user` must own it."
  @spec pause_monitor(User.t(), Monitor.t()) ::
          {:ok, Monitor.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def pause_monitor(%User{} = user, %Monitor{} = monitor) do
    update_monitor(user, monitor, %{active: false})
  end

  @doc "Resumes a paused monitor (sets `active: true`). `user` must own it."
  @spec resume_monitor(User.t(), Monitor.t()) ::
          {:ok, Monitor.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def resume_monitor(%User{} = user, %Monitor{} = monitor) do
    update_monitor(user, monitor, %{active: true})
  end

  @doc "A changeset for building/editing a monitor form. No authorization needed — it doesn't touch the database."
  @spec change_monitor(Monitor.t(), map()) :: Ecto.Changeset.t()
  def change_monitor(%Monitor{} = monitor, attrs \\ %{}) do
    Monitor.changeset(monitor, attrs)
  end

  defp scope_to_user(query, %User{id: user_id}) do
    where(query, [m], m.user_id == ^user_id)
  end

  defp authorize(%User{id: user_id}, %Monitor{user_id: user_id}), do: :ok
  defp authorize(_user, _monitor), do: {:error, :not_found}

  ## Checks

  @doc "Records a check result for a monitor."
  @spec create_check(Monitor.t(), map()) :: {:ok, Check.t()} | {:error, Ecto.Changeset.t()}
  def create_check(%Monitor{} = monitor, attrs) do
    %Check{monitor_id: monitor.id}
    |> Check.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists a monitor's most recent checks, newest first."
  @spec list_recent_checks(Monitor.t(), pos_integer()) :: [Check.t()]
  def list_recent_checks(%Monitor{} = monitor, limit \\ 20) do
    Check
    |> where([c], c.monitor_id == ^monitor.id)
    |> order_by([c], desc: c.checked_at)
    |> limit(^limit)
    |> Repo.all()
  end

  ## Incidents

  @doc "Fetches a monitor's currently-open incident, if any."
  @spec get_open_incident(Monitor.t()) :: {:ok, Incident.t()} | {:error, :not_found}
  def get_open_incident(%Monitor{} = monitor) do
    Incident
    |> where([i], i.monitor_id == ^monitor.id and is_nil(i.resolved_at))
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      incident -> {:ok, incident}
    end
  end

  @doc """
  Opens a new incident for a monitor. Fails with a changeset error (via the
  database's partial unique index) if the monitor already has one open —
  callers should check `get_open_incident/1` first, but this is the actual
  source of truth under concurrent checks.
  """
  @spec open_incident(Monitor.t(), DateTime.t()) ::
          {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
  def open_incident(%Monitor{} = monitor, started_at \\ DateTime.utc_now()) do
    %Incident{monitor_id: monitor.id}
    |> Incident.open_changeset(%{started_at: started_at})
    |> Repo.insert()
  end

  @doc "Resolves an open incident, optionally attaching an AI-generated summary."
  @spec resolve_incident(Incident.t(), DateTime.t(), String.t() | nil) ::
          {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
  def resolve_incident(
        %Incident{} = incident,
        resolved_at \\ DateTime.utc_now(),
        ai_summary \\ nil
      ) do
    incident
    |> Incident.resolve_changeset(%{resolved_at: resolved_at, ai_summary: ai_summary})
    |> Repo.update()
  end

  @doc "Lists a monitor's incidents, most recently started first."
  @spec list_incidents(Monitor.t()) :: [Incident.t()]
  def list_incidents(%Monitor{} = monitor) do
    Incident
    |> where([i], i.monitor_id == ^monitor.id)
    |> order_by([i], desc: i.started_at)
    |> Repo.all()
  end
end
