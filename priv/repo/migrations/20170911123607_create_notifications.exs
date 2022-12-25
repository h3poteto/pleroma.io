# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:notifications) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:activity_id, references(:activities, on_delete: :delete_all))
      add(:seen, :boolean, default: false)

      timestamps()
    end

    create_if_not_exists(index(:notifications, [:user_id]))
  end
end
