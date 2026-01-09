defmodule Pleroma.Web.ApiSpec.PleromaFrontendSettingsOperation do
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Schema
  import Pleroma.Web.ApiSpec.Helpers

  @spec open_api_operation(atom) :: Operation.t()
  def open_api_operation(action) do
    operation = String.to_existing_atom("#{action}_operation")
    apply(__MODULE__, operation, [])
  end

  def available_frontends_operation do
    %Operation{
      tags: ["Preferred frontends"],
      summary: "Frontend settings profiles",
      description: "List frontend setting profiles",
      operationId: "PleromaAPI.FrontendSettingsController.available_frontends",
      responses: %{
        200 =>
          Operation.response("Frontends", "application/json", %Schema{
            type: :array,
            items: %Schema{
              type: :string
            }
          })
      }
    }
  end

  def update_preferred_frontend_operation do
    %Operation{
      tags: ["Preferred frontends"],
      summary: "Update preferred frontend setting",
      description: "Store preferred frontend in cookies",
      operationId: "PleromaAPI.FrontendSettingsController.update_preferred_frontend",
      requestBody:
        request_body(
          "Frontend",
          %Schema{
            type: :object,
            required: [:frontend_name],
            properties: %{
              frontend_name: %Schema{
                type: :string,
                description: "Frontend name"
              }
            }
          },
          required: true
        ),
      responses: %{
        200 =>
          Operation.response("Preferred frontend", "application/json", %Schema{
            type: :object,
            properties: %{
              frontend_name: %Schema{
                type: :string,
                description: "Frontend name"
              }
            }
          })
      }
    }
  end
end
