defmodule Pulsewatch.Monitoring.Monitor do
  @moduledoc """
  A website to periodically check. Owned by exactly one user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "monitors" do
    field :name, :string
    field :check_type, Ecto.Enum, values: [:http, :tcp], default: :http
    field :url, :string
    field :host, :string
    field :port, :integer
    field :check_interval_seconds, :integer, default: 60
    field :expected_status_code, :integer, default: 200
    field :timeout_ms, :integer, default: 5_000
    field :active, :boolean, default: true
    field :webhook_url, :string

    belongs_to :user, Pulsewatch.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(monitor, attrs) do
    monitor
    |> cast(attrs, [
      :name,
      :check_type,
      :url,
      :host,
      :port,
      :check_interval_seconds,
      :expected_status_code,
      :timeout_ms,
      :active,
      :webhook_url
    ])
    |> validate_required([:name, :check_type])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_target()
    |> validate_url(:webhook_url, allow_blank?: true)
    |> validate_number(:check_interval_seconds,
      greater_than_or_equal_to: 30,
      less_than_or_equal_to: 3600
    )
    |> validate_number(:expected_status_code,
      greater_than_or_equal_to: 100,
      less_than_or_equal_to: 599
    )
    |> validate_number(:timeout_ms, greater_than_or_equal_to: 100, less_than_or_equal_to: 60_000)
  end

  @doc "A human-readable description of what this monitor checks: its URL for an HTTP monitor, `host:port` for a TCP one."
  @spec target(t()) :: String.t()
  def target(%__MODULE__{check_type: :http, url: url}), do: url
  def target(%__MODULE__{check_type: :tcp, host: host, port: port}), do: "#{host}:#{port}"

  # Which fields are required, and how they're validated, depends on
  # check_type: an :http monitor needs a URL, a :tcp one needs a
  # host and port. Each is the other's don't-care — a :tcp monitor can
  # carry a stale url from before it was switched, same as a :http one
  # ignores host/port, since only the active type's fields are ever
  # read (Checker.run/2 dispatches on check_type, not on which fields
  # happen to be set).
  defp validate_target(changeset) do
    case get_field(changeset, :check_type) do
      :http -> changeset |> validate_required([:url]) |> validate_url(:url)
      :tcp -> changeset |> validate_required([:host, :port]) |> validate_host() |> validate_port()
      _ -> changeset
    end
  end

  defp validate_host(changeset) do
    validate_change(changeset, :host, fn :host, value ->
      if String.contains?(value, "://") do
        [host: "should be a bare hostname or IP, not a URL"]
      else
        []
      end
    end)
  end

  defp validate_port(changeset) do
    validate_number(changeset, :port, greater_than_or_equal_to: 1, less_than_or_equal_to: 65_535)
  end

  defp validate_url(changeset, field, opts \\ []) do
    allow_blank? = Keyword.get(opts, :allow_blank?, false)

    validate_change(changeset, field, fn ^field, value ->
      cond do
        allow_blank? and (is_nil(value) or value == "") ->
          []

        valid_http_url?(value) ->
          []

        true ->
          [{field, "must be a valid http or https URL"}]
      end
    end)
  end

  defp valid_http_url?(value) when is_binary(value) do
    case URI.new(value) do
      {:ok, %URI{scheme: scheme, host: host}} when scheme in ["http", "https"] ->
        is_binary(host) and host != ""

      _ ->
        false
    end
  end

  defp valid_http_url?(_), do: false
end
