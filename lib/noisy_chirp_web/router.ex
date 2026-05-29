defmodule ChirpWeb.Router do
  use ChirpWeb, :router

  import ChirpWeb.Auth, only: [require_authenticated_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChirpWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_auth do
    plug :require_authenticated_user
  end

  scope "/", ChirpWeb do
    pipe_through :browser

    # Public landing — just the logo.
    get "/", PageController, :landing

    # Login / logout
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    # Public confirm + oath pages (auth via unguessable token).
    live "/t/:token", ConfirmLive, :show
    live "/oath/:token", OathLive, :show
  end

  scope "/admin", ChirpWeb do
    pipe_through [:browser, :require_auth]

    live_session :admin,
      on_mount: [{ChirpWeb.Auth, :ensure_authenticated}] do
      live "/", DashboardLive, :index
      live "/new", NewTaskLive, :new
      live "/:id/edit", EditTaskLive, :edit
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:noisy_chirp, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ChirpWeb.Telemetry
    end
  end
end
