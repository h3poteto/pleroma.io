# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.StatusControllerTest do
  use Pleroma.Web.ConnCase

  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  test "/quotes fallback works" do
    [current_user, user] = insert_pair(:user)
    %{conn: conn} = oauth_access(["read:statuses"], user: current_user)

    activity = insert(:note_activity)

    {:ok, quote_post} = CommonAPI.post(user, %{status: "quoat", quoted_status_id: activity.id})

    response =
      conn
      |> get("/api/v1/pleroma/statuses/#{activity.id}/quotes")
      |> json_response_and_validate_schema(:ok)

    [status] = response

    assert length(response) == 1
    assert status["id"] == quote_post.id
  end
end
