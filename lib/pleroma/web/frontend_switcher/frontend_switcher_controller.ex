defmodule Pleroma.Web.FrontendSwitcher.FrontendSwitcherController do
  use Pleroma.Web, :controller
  alias Pleroma.Config

  @doc "GET /frontend_switcher"
  def switch(conn, _params) do
    pickable = Config.get([:frontends, :pickable], [])

    conn
    |> put_view(Pleroma.Web.FrontendSwitcher.FrontendSwitcherView)
    |> render("switch.html", choices: pickable)
  end

  @doc "POST /frontend_switcher"
  def do_switch(conn, params) do
    conn
    |> put_resp_cookie("preferred_frontend", params["frontend"])
    |> html(~s(<meta http-equiv="refresh" content="0; url=/">))
  end
end
