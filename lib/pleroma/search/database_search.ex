# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Search.DatabaseSearch do
  alias Pleroma.Activity
  alias Pleroma.Config
  alias Pleroma.Object.Fetcher
  alias Pleroma.Pagination
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Visibility

  require Pleroma.Constants

  import Ecto.Query

  @behaviour Pleroma.Search.SearchBackend

  @impl true
  def search(user, search_query, options \\ []) do
    index_type = if Config.get([:database, :rum_enabled]), do: :rum, else: :gin
    limit = Enum.min([Keyword.get(options, :limit), 40])
    offset = Keyword.get(options, :offset, 0)
    author = Keyword.get(options, :author)

    try do
      Activity
      |> Activity.with_preloaded_object()
      |> Activity.restrict_deactivated_users()
      |> restrict_public(user)
      |> query_with(index_type, search_query)
      |> maybe_restrict_local(user)
      |> maybe_restrict_author(author)
      |> maybe_restrict_blocked(user)
      |> Pagination.fetch_paginated(
        %{"offset" => offset, "limit" => limit, "skip_order" => index_type == :rum},
        :offset
      )
      |> maybe_fetch(user, search_query)
    rescue
      _ -> maybe_fetch([], user, search_query)
    end
  end

  @impl true
  def add_to_index(_activity), do: :ok

  @impl true
  def remove_from_index(_object), do: :ok

  @impl true
  def create_index, do: :ok

  @impl true
  def drop_index, do: :ok

  @impl true
  def healthcheck_endpoints, do: nil

  def maybe_restrict_author(query, %User{} = author) do
    Activity.Queries.by_author(query, author)
  end

  def maybe_restrict_author(query, _), do: query

  def maybe_restrict_blocked(query, %User{} = user) do
    Activity.Queries.exclude_authors(query, User.blocked_users_ap_ids(user))
  end

  def maybe_restrict_blocked(query, _), do: query

  defp restrict_public(q, user) when not is_nil(user) do
    intended_recipients = [
      Pleroma.Constants.as_public(),
      Pleroma.Web.ActivityPub.Utils.as_local_public()
    ]

    from([a, o] in q,
      where: fragment("?->>'type' = 'Create'", a.data),
      where: fragment("? && ?", ^intended_recipients, a.recipients)
    )
  end

  defp restrict_public(q, _user) do
    from([a, o] in q,
      where: fragment("?->>'type' = 'Create'", a.data),
      where: ^Pleroma.Constants.as_public() in a.recipients
    )
  end

  defp query_with(q, :gin, search_query) do
    %{rows: [[tsc]]} =
      Ecto.Adapters.SQL.query!(
        Pleroma.Repo,
        "select current_setting('default_text_search_config')::regconfig::oid;"
      )

    from([a, o] in q,
      where:
        fragment(
          "to_tsvector(?::oid::regconfig, ?->>'content') @@ websearch_to_tsquery(?)",
          ^tsc,
          o.data,
          ^search_query
        )
    )
  end

  defp query_with(q, :rum, search_query) do
    from([a, o] in q,
      where:
        fragment(
          "? @@ websearch_to_tsquery(?)",
          o.fts_content,
          ^search_query
        ),
      order_by: [fragment("? <=> now()::date", o.inserted_at)]
    )
  end

  def maybe_restrict_local(q, user) do
    limit = Config.get([:instance, :limit_to_local_content], :unauthenticated)

    case {limit, user} do
      {:all, _} -> restrict_local(q)
      {:unauthenticated, %User{}} -> q
      {:unauthenticated, _} -> restrict_local(q)
      {false, _} -> q
    end
  end

  defp restrict_local(q), do: where(q, local: true)

  def maybe_fetch(activities, user, search_query) do
    with true <- Regex.match?(~r/https?:/, search_query),
         {:ok, object} <- Fetcher.fetch_object_from_id(search_query),
         %Activity{} = activity <- Activity.get_create_by_object_ap_id(object.data["id"]),
         true <- Visibility.visible_for_user?(activity, user) do
      [activity | activities]
    else
      _ -> activities
    end
  end
end