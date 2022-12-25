# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.UsersAddLastRefreshedAt do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:last_refreshed_at, :naive_datetime_usec)
    end
  end
end
