# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaApi.InstancesControllerTest do
  use Pleroma.Web.ConnCase

  alias Pleroma.Instances

  setup do
    constant = "http://consistently-unreachable.name/"

    {:ok, %Pleroma.Instances.Instance{unreachable_since: constant_unreachable}} =
      Instances.set_unreachable(constant)

    %{constant_unreachable: constant_unreachable, constant: constant}
  end

  test "GET /api/v1/pleroma/federation_status", %{
    conn: conn,
    constant_unreachable: constant_unreachable,
    constant: constant
  } do
    clear_config([:instance, :public], false)

    constant_host = URI.parse(constant).host

    assert conn
           |> put_req_header("content-type", "application/json")
           |> get("/api/v1/pleroma/federation_status")
           |> json_response_and_validate_schema(200) == %{
             "unreachable" => %{constant_host => to_string(constant_unreachable)}
           }
  end
end
