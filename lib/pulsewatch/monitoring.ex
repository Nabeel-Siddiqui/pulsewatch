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

  ## PubSub
  #
  # Topic names are constructed only here, so publisher (the checking
  # engine) and subscribers (LiveViews) can never drift out of sync on the
  # topic string. Two topics per check: one scoped to the monitor (the
  # detail page only cares about its own monitor) and one scoped to the
  # user (the dashboard cares about all of a user's monitors, and must
  # never receive another user's data).

  @doc "Subscribes the calling process to updates for all of `user`'s monitors (dashboard)."
  @spec subscribe_to_user_monitors(User.t()) :: :ok | {:error, term()}
  def subscribe_to_user_monitors(%User{} = user) do
    Phoenix.PubSub.subscribe(Pulsewatch.PubSub, user_topic(user.id))
  end

  @doc "Subscribes the calling process to updates for a single monitor (detail page)."
  @spec subscribe_to_monitor(Monitor.t()) :: :ok | {:error, term()}
  def subscribe_to_monitor(%Monitor{} = monitor) do
    Phoenix.PubSub.subscribe(Pulsewatch.PubSub, monitor_topic(monitor.id))
  end

  @doc false
  @spec broadcast(Monitor.t(), term()) :: :ok
  def broadcast(%Monitor{} = monitor, message) do
    Phoenix.PubSub.broadcast(Pulsewatch.PubSub, monitor_topic(monitor.id), message)
    Phoenix.PubSub.broadcast(Pulsewatch.PubSub, user_topic(monitor.user_id), message)
  end

  defp user_topic(user_id), do: "user:#{user_id}:monitors"
  defp monitor_topic(monitor_id), do: "monitor:#{monitor_id}"

  @type dashboard_row :: %{
          monitor: Monitor.t(),
          status: :up | :down | nil,
          last_response_time_ms: non_neg_integer() | nil,
          last_checked_at: DateTime.t() | nil,
          uptime_pct: float() | nil
        }

  @doc """
  One row per monitor, each with its latest check status/response time
  and its uptime percentage over the last 24h — computed with two
  `LEFT LATERAL` joins in a single query, not one query per monitor (or
  two: "latest check" and "24h uptime" are different row sets — a
  monitor with no checks in the last 24h should still show its actual
  last-known status, not go blank).
  """
  @spec dashboard_rows(User.t()) :: [dashboard_row()]
  def dashboard_rows(%User{} = user) do
    since = DateTime.add(DateTime.utc_now(), -24, :hour)

    latest_check =
      from c in Check,
        where: c.monitor_id == parent_as(:monitor).id,
        order_by: [desc: c.checked_at],
        limit: 1,
        select: %{
          status: c.status,
          response_time_ms: c.response_time_ms,
          checked_at: c.checked_at
        }

    uptime_counts =
      from c in Check,
        where: c.monitor_id == parent_as(:monitor).id and c.checked_at >= ^since,
        select: %{total: count(c.id), up: filter(count(c.id), c.status == :up)}

    query =
      from m in Monitor,
        as: :monitor,
        where: m.user_id == ^user.id,
        left_lateral_join: latest in subquery(latest_check),
        on: true,
        left_lateral_join: uptime in subquery(uptime_counts),
        on: true,
        order_by: [asc: m.name],
        select: %{monitor: m, latest: latest, uptime: uptime}

    query
    |> Repo.all()
    |> Enum.map(&to_dashboard_row/1)
  end

  defp to_dashboard_row(%{monitor: monitor, latest: latest, uptime: uptime}) do
    %{
      monitor: monitor,
      status: latest && latest.status,
      last_response_time_ms: latest && latest.response_time_ms,
      last_checked_at: latest && latest.checked_at,
      uptime_pct: uptime_percentage(uptime)
    }
  end

  defp uptime_percentage(%{total: total, up: up}) when is_integer(total) and total > 0 do
    Float.round(up / total * 100, 1)
  end

  defp uptime_percentage(_uptime), do: nil

  ## Monitors

  @doc """
  Lists every active monitor, across all users. Not user-scoped —
  intentionally not called from the web layer, only used to boot the
  checking engine's workers on application start (and after a crash).
  """
  @spec list_active_monitors() :: [Monitor.t()]
  def list_active_monitors do
    Monitor
    |> where([m], m.active == true)
    |> Repo.all()
  end

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

  @doc """
  Lists a monitor's checks from the last `hours`, oldest first — the shape
  the detail page's response-time chart wants (chronological, for a
  time-series line).
  """
  @spec list_checks_since(Monitor.t(), pos_integer()) :: [Check.t()]
  def list_checks_since(%Monitor{} = monitor, hours \\ 24) do
    since = DateTime.add(DateTime.utc_now(), -hours, :hour)

    Check
    |> where([c], c.monitor_id == ^monitor.id and c.checked_at >= ^since)
    |> order_by([c], asc: c.checked_at)
    |> Repo.all()
  end

  @doc """
  Deletes checks older than `days`. Returns the number of rows deleted.
  Used by the nightly retention Oban job — not exposed to the web layer.
  """
  @spec delete_checks_older_than(pos_integer()) :: non_neg_integer()
  def delete_checks_older_than(days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    {count, nil} = Repo.delete_all(where(Check, [c], c.checked_at < ^cutoff))
    count
  end

  @doc """
  Lists a monitor's checks between `from` and `to` (inclusive), oldest
  first — the incident-summary worker's view of "what happened during
  this outage."
  """
  @spec list_checks_during(Monitor.t(), DateTime.t(), DateTime.t()) :: [Check.t()]
  def list_checks_during(%Monitor{} = monitor, %DateTime{} = from, %DateTime{} = to) do
    Check
    |> where([c], c.monitor_id == ^monitor.id and c.checked_at >= ^from and c.checked_at <= ^to)
    |> order_by([c], asc: c.checked_at)
    |> Repo.all()
  end

  ## Incidents

  @doc "Fetches an incident by id, with its monitor and the monitor's owning user preloaded. Not user-scoped — for system code (the alert worker), not the web layer."
  @spec get_incident!(term()) :: Incident.t()
  def get_incident!(id) do
    Incident
    |> Repo.get!(id)
    |> Repo.preload(monitor: :user)
  end

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

  @doc """
  Same as `open_incident/2`, but returns an unrun `Ecto.Multi` (named step
  `:incident`) instead of inserting directly — lets a caller (`Alerts`)
  compose the incident insert and an Oban job insert into one transaction,
  so an incident is never recorded without its alert being queued, or
  vice versa.
  """
  @spec open_incident_multi(Monitor.t(), DateTime.t()) :: Ecto.Multi.t()
  def open_incident_multi(%Monitor{} = monitor, started_at \\ DateTime.utc_now()) do
    changeset =
      Incident.open_changeset(%Incident{monitor_id: monitor.id}, %{started_at: started_at})

    Ecto.Multi.new() |> Ecto.Multi.insert(:incident, changeset)
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

  @doc "Same as `resolve_incident/3`, but returns an unrun `Ecto.Multi` — see `open_incident_multi/2`."
  @spec resolve_incident_multi(Incident.t(), DateTime.t(), String.t() | nil) :: Ecto.Multi.t()
  def resolve_incident_multi(
        %Incident{} = incident,
        resolved_at \\ DateTime.utc_now(),
        ai_summary \\ nil
      ) do
    changeset =
      Incident.resolve_changeset(incident, %{resolved_at: resolved_at, ai_summary: ai_summary})

    Ecto.Multi.new() |> Ecto.Multi.update(:incident, changeset)
  end

  @doc """
  Attaches an AI-generated summary to an already-resolved incident.
  Separate from `resolve_incident/3` because the summary is generated
  asynchronously, well after resolution — by the AI summary worker,
  which may finish seconds (or never, if the LLM call fails) after the
  incident itself resolved.
  """
  @spec update_incident_summary(Incident.t(), String.t()) ::
          {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
  def update_incident_summary(%Incident{} = incident, ai_summary) when is_binary(ai_summary) do
    incident
    |> Incident.summary_changeset(%{ai_summary: ai_summary})
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
