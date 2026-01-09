# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ApiSpec.Schemas.ApiNotFoundError do
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Not Found",
    description: "Response schema for 404 API errors",
    type: :object,
    properties: %{error: %Schema{type: :string}},
    example: %{
      "error" => "Record not found"
    }
  })
end
