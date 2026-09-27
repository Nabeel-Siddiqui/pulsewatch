defmodule PulsewatchWeb.HealthControllerTest do
  use PulsewatchWeb.ConnCase, async: true

  test "reports ok status, database connectivity, and a worker count, with no auth required", %{
    conn: conn
  } do
    conn = get(conn, ~p"/health")

    assert %{"status" => "ok", "database" => "ok", "workers" => workers} =
             json_response(conn, 200)

    assert is_integer(workers)
  end
end
