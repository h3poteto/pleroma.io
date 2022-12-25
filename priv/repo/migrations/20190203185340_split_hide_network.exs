# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.SplitHideNetwork do
  use Ecto.Migration

  def up do
    execute(
      "UPDATE users SET info = jsonb_set(info, '{hide_network}'::text[], 'false'::jsonb) WHERE NOT(info::jsonb ? 'hide_network') AND local"
    )

    execute(
      "UPDATE users SET info = jsonb_set(info, '{hide_followings}'::text[], info->'hide_network') WHERE local"
    )

    execute(
      "UPDATE users SET info = jsonb_set(info, '{hide_followers}'::text[], info->'hide_network') WHERE local"
    )
  end

  def down do
  end
end
