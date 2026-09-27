defmodule PulsewatchWeb.ApiSpec do
  @moduledoc "OpenAPI 3 spec for the /api/v1 JSON API. Served as JSON at /api/openapi and browsable at /api/swaggerui."

  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}
  alias PulsewatchWeb.{Endpoint, Router}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [Server.from_endpoint(Endpoint)],
      info: %Info{
        title: "Pulsewatch API",
        version: "1",
        description: """
        Read-only JSON API for your monitors, their check history, and
        incidents. Authenticate with a personal access token
        (Settings -> API tokens) as a bearer token:

            Authorization: Bearer <token>

        Rate-limited per token — see the `Retry-After` header on a 429.
        """
      },
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{type: "http", scheme: "bearer"}
        }
      },
      security: [%{"bearerAuth" => []}]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
