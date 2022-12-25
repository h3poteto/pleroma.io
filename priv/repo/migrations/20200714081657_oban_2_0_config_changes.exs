# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Elixir.Pleroma.Repo.Migrations.Oban20ConfigChanges do
  use Ecto.Migration
  import Ecto.Query
  alias Pleroma.ConfigDB
  alias Pleroma.Repo

  def change do
    config_entry =
      from(c in ConfigDB, where: c.group == ^":pleroma" and c.key == ^"Oban")
      |> select([c], struct(c, [:value, :id]))
      |> Repo.one()

    if config_entry do
      %{value: value} = config_entry

      value =
        case Keyword.fetch(value, :verbose) do
          {:ok, log} -> Keyword.put_new(value, :log, log)
          _ -> value
        end
        |> Keyword.drop([:verbose, :prune])

      Ecto.Changeset.change(config_entry, %{value: value})
      |> Repo.update()
    end
  end
end
