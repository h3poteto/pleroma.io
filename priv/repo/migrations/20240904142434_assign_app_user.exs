defmodule Pleroma.Repo.Migrations.AssignAppUser do
  use Ecto.Migration

  import Ecto.Query

  alias Pleroma.Repo
  alias Pleroma.Web.OAuth.App
  alias Pleroma.Web.OAuth.Token

  def up do
    Token
    |> where([t], not is_nil(t.user_id))
    |> group_by([t], t.app_id)
    |> select([t], %{app_id: t.app_id, id: min(t.id)})
    |> order_by(asc: :app_id)
    |> Repo.stream()
    |> Stream.each(fn %{id: id} ->
      token = Token.Query.get_by_id(id) |> Repo.one()
      App.maybe_update_owner(token)
    end)
    |> Stream.run()
  end

  def down, do: :ok
end
