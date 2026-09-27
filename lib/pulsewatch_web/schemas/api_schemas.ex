defmodule PulsewatchWeb.Schemas do
  @moduledoc "OpenAPI schema definitions for the /api/v1 JSON API's request/response bodies."

  alias OpenApiSpex.Schema

  defmodule Monitor do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Monitor",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        name: %Schema{type: :string},
        url: %Schema{type: :string, format: :uri},
        check_interval_seconds: %Schema{type: :integer},
        expected_status_code: %Schema{type: :integer},
        timeout_ms: %Schema{type: :integer},
        active: %Schema{type: :boolean},
        webhook_url: %Schema{type: :string, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :url, :active],
      example: %{
        "id" => 1,
        "name" => "Marketing site",
        "url" => "https://example.com",
        "check_interval_seconds" => 60,
        "expected_status_code" => 200,
        "timeout_ms" => 5000,
        "active" => true,
        "webhook_url" => nil,
        "inserted_at" => "2026-01-01T12:00:00Z"
      }
    })
  end

  defmodule MonitorsResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MonitorsResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: Monitor}},
      required: [:data]
    })
  end

  defmodule MonitorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MonitorResponse",
      type: :object,
      properties: %{data: Monitor},
      required: [:data]
    })
  end

  defmodule Check do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Check",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        status: %Schema{type: :string, enum: ["up", "down"]},
        status_code: %Schema{type: :integer, nullable: true},
        response_time_ms: %Schema{type: :integer, nullable: true},
        error_message: %Schema{type: :string, nullable: true},
        checked_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :status, :checked_at],
      example: %{
        "id" => 42,
        "status" => "up",
        "status_code" => 200,
        "response_time_ms" => 88,
        "error_message" => nil,
        "checked_at" => "2026-01-01T12:00:00Z"
      }
    })
  end

  defmodule ChecksResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ChecksResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: Check}},
      required: [:data]
    })
  end

  defmodule Incident do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Incident",
      type: :object,
      properties: %{
        id: %Schema{type: :integer},
        started_at: %Schema{type: :string, format: :"date-time"},
        resolved_at: %Schema{type: :string, format: :"date-time", nullable: true},
        ai_summary: %Schema{type: :string, nullable: true}
      },
      required: [:id, :started_at],
      example: %{
        "id" => 7,
        "started_at" => "2026-01-01T12:00:00Z",
        "resolved_at" => "2026-01-01T12:05:00Z",
        "ai_summary" => "Brief outage, recovered on its own."
      }
    })
  end

  defmodule IncidentsResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "IncidentsResponse",
      type: :object,
      properties: %{data: %Schema{type: :array, items: Incident}},
      required: [:data]
    })
  end

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          properties: %{detail: %Schema{type: :string}},
          required: [:detail]
        }
      },
      required: [:errors],
      example: %{"errors" => %{"detail" => "not found"}}
    })
  end
end
