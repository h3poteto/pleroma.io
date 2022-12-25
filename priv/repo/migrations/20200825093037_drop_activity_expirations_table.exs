# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.DropActivityExpirationsTable do
  use Ecto.Migration

  def change do
    drop(table("activity_expirations"))
  end
end
