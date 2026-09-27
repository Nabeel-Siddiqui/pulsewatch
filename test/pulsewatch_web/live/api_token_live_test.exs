defmodule PulsewatchWeb.ApiTokenLiveTest do
  use PulsewatchWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Pulsewatch.Accounts

  setup :register_and_log_in_user

  test "creates a token and shows the plaintext exactly once", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/api_tokens")

    html =
      view
      |> form("#new-token-form", %{"name" => "CI token"})
      |> render_submit()

    assert html =~ "won&#39;t be shown again"
    assert html =~ "CI token"
  end

  test "lists existing tokens without ever showing their plaintext", %{conn: conn, user: user} do
    {:ok, _token, _api_token} = Accounts.create_api_token(user, "Existing token")

    {:ok, _view, html} = live(conn, ~p"/settings/api_tokens")

    assert html =~ "Existing token"
    assert html =~ "Never"
  end

  test "revokes a token", %{conn: conn, user: user} do
    {:ok, _token, api_token} = Accounts.create_api_token(user, "Doomed")
    {:ok, view, _html} = live(conn, ~p"/settings/api_tokens")

    view |> element("a", "Revoke") |> render_click()

    refute render(view) =~ "Doomed"
    assert Accounts.list_api_tokens(user) |> Enum.find(&(&1.id == api_token.id)) == nil
  end

  test "only shows the current user's tokens", %{conn: conn} do
    other_user = Pulsewatch.AccountsFixtures.user_fixture()
    {:ok, _token, _} = Accounts.create_api_token(other_user, "Not mine")

    {:ok, _view, html} = live(conn, ~p"/settings/api_tokens")

    refute html =~ "Not mine"
  end
end
