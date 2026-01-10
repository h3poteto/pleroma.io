defmodule Pleroma.Repo.Migrations.AddActivitiesActorTypeIndex do
  use Ecto.Migration
  @disable_ddl_transaction true

  def change do
    create(
      index(
        :activities,
        ["actor", "(data ->> 'type'::text)", "id DESC NULLS LAST"],
        concurrently: true
      )
    )
  end
end
