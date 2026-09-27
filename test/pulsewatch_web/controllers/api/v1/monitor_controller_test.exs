defmodule PulsewatchWeb.Api.V1.MonitorControllerTest do
  use PulsewatchWeb.ConnCase, async: true

  import Pulsewatch.MonitoringFixtures

  describe "authentication" do
    test "no Authorization header returns 401", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/monitors")
      assert json_response(conn, 401)["errors"]["detail"] =~ "missing or invalid"
    end

    test "a malformed Authorization header (no 'Bearer ' prefix) returns 401", %{conn: conn} do
      conn = conn |> put_req_header("authorization", "garbage") |> get(~p"/api/v1/monitors")
      assert json_response(conn, 401)
    end

    test "a well-formed but unknown token returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-a-real-token")
        |> get(~p"/api/v1/monitors")

      assert json_response(conn, 401)
    end

    test "a revoked token returns 401", %{conn: conn} do
      user = Pulsewatch.AccountsFixtures.user_fixture()
      {:ok, token, api_token} = Pulsewatch.Accounts.create_api_token(user, "test")
      {:ok, _} = Pulsewatch.Accounts.revoke_api_token(user, api_token)

      conn = conn |> put_api_token(token) |> get(~p"/api/v1/monitors")
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v1/monitors" do
    setup :register_user_with_api_token

    test "lists only the token owner's monitors", %{conn: conn, user: user} do
      mine = monitor_fixture(%{user: user, name: "Mine"})
      _theirs = monitor_fixture(%{name: "Not mine"})

      conn = get(conn, ~p"/api/v1/monitors")

      assert [%{"id" => id, "name" => "Mine"}] = json_response(conn, 200)["data"]
      assert id == mine.id
    end

    test "returns an empty list, not an error, when the user has no monitors", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/monitors")
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "GET /api/v1/monitors/:id" do
    setup :register_user_with_api_token

    test "returns the monitor", %{conn: conn, user: user} do
      monitor = monitor_fixture(%{user: user, name: "Example"})
      conn = get(conn, ~p"/api/v1/monitors/#{monitor.id}")

      assert %{"id" => id, "name" => "Example", "url" => _} = json_response(conn, 200)["data"]
      assert id == monitor.id
    end

    test "404s for another user's monitor — not 403, so existence isn't leaked", %{conn: conn} do
      theirs = monitor_fixture()
      conn = get(conn, ~p"/api/v1/monitors/#{theirs.id}")

      assert json_response(conn, 404)["errors"]["detail"] == "not found"
    end

    test "404s for a nonexistent id", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/monitors/999999")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/monitors/:id/checks" do
    setup :register_user_with_api_token

    test "lists the monitor's recent checks, newest first", %{conn: conn, user: user} do
      monitor = monitor_fixture(%{user: user})
      now = DateTime.utc_now()
      older = check_fixture(monitor, %{status: :up, checked_at: DateTime.add(now, -60, :second)})
      newer = check_fixture(monitor, %{status: :down, checked_at: now})

      conn = get(conn, ~p"/api/v1/monitors/#{monitor.id}/checks")

      assert [first, second] = json_response(conn, 200)["data"]
      assert first["id"] == newer.id
      assert second["id"] == older.id
    end

    test "respects a ?limit= param, capped at 100", %{conn: conn, user: user} do
      monitor = monitor_fixture(%{user: user})
      for _ <- 1..5, do: check_fixture(monitor)

      conn = get(conn, ~p"/api/v1/monitors/#{monitor.id}/checks?limit=2")
      assert length(json_response(conn, 200)["data"]) == 2
    end

    test "404s for another user's monitor", %{conn: conn} do
      theirs = monitor_fixture()
      conn = get(conn, ~p"/api/v1/monitors/#{theirs.id}/checks")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/monitors/:id/incidents" do
    setup :register_user_with_api_token

    test "lists the monitor's incidents", %{conn: conn, user: user} do
      monitor = monitor_fixture(%{user: user})
      {:ok, incident} = Pulsewatch.Monitoring.open_incident(monitor)

      conn = get(conn, ~p"/api/v1/monitors/#{monitor.id}/incidents")

      assert [%{"id" => id, "started_at" => _}] = json_response(conn, 200)["data"]
      assert id == incident.id
    end

    test "404s for another user's monitor", %{conn: conn} do
      theirs = monitor_fixture()
      conn = get(conn, ~p"/api/v1/monitors/#{theirs.id}/incidents")
      assert json_response(conn, 404)
    end
  end

  describe "rate limiting" do
    setup :register_user_with_api_token

    test "returns 429 with a Retry-After header once the per-token limit is exceeded", %{
      conn: conn
    } do
      # config/test.exs sets the limit to 3 requests per window.
      for _ <- 1..3 do
        conn = get(conn, ~p"/api/v1/monitors")
        assert conn.status == 200
      end

      conn = get(conn, ~p"/api/v1/monitors")

      assert json_response(conn, 429)["errors"]["detail"] =~ "rate limit"
      assert [_retry_after] = get_resp_header(conn, "retry-after")
    end

    test "two different tokens for the same user have independent budgets", %{
      conn: conn,
      user: user
    } do
      for _ <- 1..3, do: get(conn, ~p"/api/v1/monitors")

      {:ok, other_token, _} = Pulsewatch.Accounts.create_api_token(user, "second token")
      fresh_conn = put_api_token(Phoenix.ConnTest.build_conn(), other_token)

      conn = get(fresh_conn, ~p"/api/v1/monitors")
      assert conn.status == 200
    end
  end
end
