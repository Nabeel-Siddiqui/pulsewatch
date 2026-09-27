defmodule PulsewatchWeb.Router do
  use PulsewatchWeb, :router

  import PulsewatchWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PulsewatchWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: PulsewatchWeb.ApiSpec
  end

  pipeline :api_auth do
    plug PulsewatchWeb.Plugs.ApiAuth
    plug PulsewatchWeb.Plugs.RateLimit
  end

  scope "/", PulsewatchWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", PulsewatchWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # No PulsewatchWeb module prefix here on purpose — these two plugs are
  # OpenApiSpex's own, not ours, and a scope with a module alias silently
  # prefixes *every* bare module name in it (a real gotcha: this
  # originally resolved to the nonexistent
  # PulsewatchWeb.OpenApiSpex.Plug.RenderSpec instead of
  # OpenApiSpex.Plug.RenderSpec).
  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
    get "/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  scope "/api/v1", PulsewatchWeb.Api.V1 do
    pipe_through [:api, :api_auth]

    get "/monitors", MonitorController, :index
    get "/monitors/:id", MonitorController, :show
    get "/monitors/:id/checks", MonitorController, :checks
    get "/monitors/:id/incidents", MonitorController, :incidents
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:pulsewatch, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PulsewatchWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", PulsewatchWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{PulsewatchWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", PulsewatchWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{PulsewatchWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
      live "/settings/api_tokens", ApiTokenLive, :index

      live "/monitors", DashboardLive, :index
      live "/monitors/new", DashboardLive, :new
      live "/monitors/:id/edit", DashboardLive, :edit

      live "/monitors/:id", MonitorLive.Show, :show
      live "/monitors/:id/show/edit", MonitorLive.Show, :edit
    end
  end

  scope "/", PulsewatchWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{PulsewatchWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
