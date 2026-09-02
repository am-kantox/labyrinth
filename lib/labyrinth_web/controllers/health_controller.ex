defmodule LabyrinthWeb.HealthController do
  @moduledoc """
  A trivial health check for deploy scripts (`ops/scripts/deploy-release.sh`)
  to poll before switching traffic over to a freshly restarted release.

  Mounted with no `pipe_through` in the router, so it never touches
  session/auth plugs, and always reaches this controller regardless of the
  `Host` header a health check happens to send (nginx proxies the health
  check straight to `127.0.0.1:3060`, bypassing Host-based vhost routing
  entirely).
  """

  use LabyrinthWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end
end
