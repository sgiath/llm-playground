defmodule PlayWeb.Router do
  use PlayWeb, :router

  import SgiathAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PlayWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope
  end

  scope "/", PlayWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", PlayWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated, on_mount: {SgiathAuth, :require_authenticated} do
      live "/agent", AgentListLive
      live "/agent/:agent_id", AgentLive

      live "/conv", ConversationListLive
      live "/conv/:conv_id", ConversationLive
    end
  end

  scope "/", SgiathAuth do
    pipe_through :browser

    get "/sign-in", Controller, :sign_in
    get "/sign-up", Controller, :sign_up
    get "/sign-out", Controller, :sign_out
    get "/auth/callback", Controller, :callback
    get "/auth/refresh", Controller, :refresh
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:play, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PlayWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
