defmodule LabyrinthWeb.Router do
  use LabyrinthWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LabyrinthWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LabyrinthWeb.UserAuth, :fetch_current_player
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # No pipe_through: deploy scripts curl this directly against
  # 127.0.0.1:3060, so it must never depend on session/auth plugs (or the
  # Host header they might otherwise care about).
  scope "/", LabyrinthWeb do
    get "/healthz", HealthController, :show
  end

  scope "/auth", LabyrinthWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    post "/:provider/callback", AuthController, :callback
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :delete
  end

  scope "/", LabyrinthWeb do
    pipe_through :browser

    live_session :authenticated_player,
      on_mount: [{LabyrinthWeb.UserAuth, :mount_current_player}] do
      live "/", LobbyLive
      live "/rules", RulesLive
      live "/games/:id", GameLive
      live "/history/:id", HistoryLive
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:labyrinth, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LabyrinthWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
