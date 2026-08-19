defmodule LabyrinthWeb.Router do
  use LabyrinthWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LabyrinthWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :ensure_player_id
  end

  defp ensure_player_id(conn, _opts) do
    if Plug.Conn.get_session(conn, :player_id) do
      conn
    else
      Plug.Conn.put_session(conn, :player_id, Ecto.UUID.generate())
    end
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LabyrinthWeb do
    pipe_through :browser

    live "/", LobbyLive
    live "/games/:id", GameLive
    live "/history/:id", HistoryLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", LabyrinthWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:labyrinth, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LabyrinthWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
