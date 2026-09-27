defmodule PulsewatchWeb.Api.FallbackController do
  @moduledoc "Translates action results the API controllers don't handle directly into JSON error responses."

  use PulsewatchWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "not found"}})
  end
end
