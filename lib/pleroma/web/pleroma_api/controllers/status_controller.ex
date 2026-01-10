# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.StatusController do
  use Pleroma.Web, :controller

  require Ecto.Query
  require Pleroma.Constants

  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(Pleroma.Web.ApiSpec.CastAndValidate)

  action_fallback(Pleroma.Web.MastodonAPI.FallbackController)

  plug(
    OAuthScopesPlug,
    %{scopes: ["read:statuses"], fallback: :proceed_unauthenticated} when action == :quotes
  )

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.PleromaStatusOperation

  @doc "GET /api/v1/pleroma/statuses/:id/quotes"
  def quotes(conn, _params) do
    conn
    |> put_view(Pleroma.Web.MastodonAPI.StatusView)
    |> Pleroma.Web.MastodonAPI.StatusController.call(:quotes)
  end
end
