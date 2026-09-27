defmodule Pulsewatch.Repo do
  use Ecto.Repo,
    otp_app: :pulsewatch,
    adapter: Ecto.Adapters.Postgres
end
