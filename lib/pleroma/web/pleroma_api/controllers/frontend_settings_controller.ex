defmodule Pleroma.Web.PleromaAPI.FrontendSettingsController do
  use Pleroma.Web, :controller

  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(
    OAuthScopesPlug,
    %{fallback: :proceed_unauthenticated, scopes: []}
    when action in [
           :available_frontends,
           :update_preferred_frontend
         ]
  )

  plug(Pleroma.Web.ApiSpec.CastAndValidate)
  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.PleromaFrontendSettingsOperation

  action_fallback(Pleroma.Web.MastodonAPI.FallbackController)

  @doc "GET /api/v1/pleroma/preferred_frontend/available"
  def available_frontends(conn, _params) do
    available = Pleroma.Config.get([:frontends, :pickable])

    conn
    |> json(available)
  end

  @doc "PUT /api/v1/pleroma/preferred_frontend"
  def update_preferred_frontend(
        %{body_params: %{frontend_name: preferred_frontend}} = conn,
        _params
      ) do
    conn
    |> put_resp_cookie("preferred_frontend", preferred_frontend)
    |> json(%{frontend_name: preferred_frontend})
  end
end
