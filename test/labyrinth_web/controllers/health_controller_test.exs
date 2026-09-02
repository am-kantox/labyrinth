defmodule LabyrinthWeb.HealthControllerTest do
  use LabyrinthWeb.ConnCase

  test "GET /healthz returns 200 ok as plain text", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert response(conn, 200) == "ok"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end
end
