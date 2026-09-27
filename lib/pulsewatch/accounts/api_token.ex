defmodule Pulsewatch.Accounts.ApiToken do
  @moduledoc """
  A personal access token for the JSON API. The plaintext token is shown
  to the user exactly once, at creation — only its SHA-256 hash is ever
  persisted, so a database leak doesn't hand out usable credentials.

  Unlike a password, this doesn't need a slow hash (bcrypt/argon2): the
  token itself is 256 bits of `:crypto.strong_rand_bytes/1` randomness,
  not a human-chosen secret, so there's no dictionary or brute-force
  attack surface a slow hash would be defending against — a fast
  cryptographic hash is the same tradeoff GitHub/Stripe-style API tokens
  make, and it keeps every authenticated API request from paying a
  deliberately-slow hashing cost.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @token_bytes 32

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :binary
    field :last_used_at, :utc_datetime

    belongs_to :user, Pulsewatch.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Generates a new random token and its changeset for `user`. Returns
  `{plaintext_token, changeset}` — the plaintext is only ever available
  here, at creation; callers must display or deliver it immediately, it
  cannot be recovered afterward.
  """
  @spec build(Pulsewatch.Accounts.User.t(), String.t()) :: {String.t(), Ecto.Changeset.t()}
  def build(user, name) do
    token = @token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    changeset =
      %__MODULE__{user_id: user.id}
      |> cast(%{name: name, token_hash: hash(token)}, [:name, :token_hash])
      |> validate_required([:name, :token_hash])
      |> validate_length(:name, min: 1, max: 100)
      |> unique_constraint(:token_hash)

    {token, changeset}
  end

  @doc "Hashes a plaintext token for lookup/comparison — never store or compare the plaintext directly."
  @spec hash(String.t()) :: binary()
  def hash(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  @doc "Changeset for recording that a token was just used to authenticate a request."
  def touch_changeset(api_token) do
    change(api_token, last_used_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
