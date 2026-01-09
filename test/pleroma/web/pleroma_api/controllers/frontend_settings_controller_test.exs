defmodule Pleroma.Web.PleromaAPI.FrontendSettingsControllerTest do
  use Pleroma.Web.ConnCase, async: false

  describe "PUT /api/v1/pleroma/preferred_frontend" do
    test "sets a cookie with selected frontend" do
      %{conn: conn} = oauth_access(["read"])

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/api/v1/pleroma/preferred_frontend", %{"frontend_name" => "pleroma-fe/stable"})

      json_response_and_validate_schema(response, 200)
      assert %{"preferred_frontend" => %{value: "pleroma-fe/stable"}} = response.resp_cookies
    end
  end
end
