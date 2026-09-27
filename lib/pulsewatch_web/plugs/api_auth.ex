defmodule PulsewatchWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates JSON API requests via a bearer token
  (`Authorization: Bearer <token>`). Assigns `:current_user` and
  `:current_api_token` on success; halts with 401 otherwise. Missing
  header, malformed header, and an unrecognized token all get the same
  generic message — distinguishing them would tell a caller more than
  they need to know about why their request failed.

  Assigning the token record (not just the user) is what lets
  `RateLimit` key by token rather than by account, downstream.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Pulsewatch.Accounts

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with [header] <- get_req_header(conn, "authorization"),
         "Bearer " <> token <- header,
         {:ok, user, api_token} <- Accounts.get_user_by_api_token(String.trim(token)) do
      conn
      |> assign(:current_user, user)
      |> assign(:current_api_token, api_token)
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{errors: %{detail: "missing or invalid API token"}})
    |> halt()
  end
end
