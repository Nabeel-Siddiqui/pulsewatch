defmodule Pulsewatch.Monitoring.Monitor do
  @moduledoc """
  A website to periodically check. Owned by exactly one user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "monitors" do
    field :name, :string
    field :url, :string
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
      :url,
      :check_interval_seconds,
      :expected_status_code,
      :timeout_ms,
      :active,
      :webhook_url
    ])
    |> validate_required([:name, :url])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_url(:url)
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
