# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Repo.Migrations.PopulateUserRawBio do
  use Ecto.Migration
  import Ecto.Query
  alias Pleroma.User
  alias Pleroma.Repo

  def change do
    {:ok, _} = Application.ensure_all_started(:fast_sanitize)

    User.Query.build(%{local: true})
    |> select([u], struct(u, [:id, :ap_id, :bio]))
    |> Repo.stream()
    |> Enum.each(fn %{bio: bio} = user ->
      if bio do
        raw_bio =
          bio
          |> String.replace(~r(<br */?>), "\n")
          |> Pleroma.HTML.strip_tags()

        Ecto.Changeset.cast(user, %{raw_bio: raw_bio}, [:raw_bio])
        |> Repo.update()
      end
    end)
  end
end
