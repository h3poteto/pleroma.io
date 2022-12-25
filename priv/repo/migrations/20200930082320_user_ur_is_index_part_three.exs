# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.UserURIsIndexPartThree do
  use Ecto.Migration

  def change do
    drop_if_exists(unique_index(:users, :uri))
    create_if_not_exists(index(:users, :uri))
  end
end
