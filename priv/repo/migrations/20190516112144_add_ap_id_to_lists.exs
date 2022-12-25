# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.AddApIdToLists do
  use Ecto.Migration

  def up do
    alter table(:lists) do
      add(:ap_id, :string)
    end

    execute("""
    UPDATE lists
    SET ap_id = u.ap_id || '/lists/' || lists.id
    FROM users AS u
    WHERE lists.user_id = u.id
    """)

    create(unique_index(:lists, :ap_id))
  end

  def down do
    drop(index(:lists, [:ap_id]))

    alter table(:lists) do
      remove(:ap_id)
    end
  end
end
