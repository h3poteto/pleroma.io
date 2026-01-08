# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Hashtag do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Ecto.Multi
  alias Pleroma.Hashtag
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User.HashtagFollow

  schema "hashtags" do
    field(:name, :string)

    many_to_many(:objects, Object, join_through: "hashtags_objects", on_replace: :delete)

    timestamps()
  end

  def normalize_name(name) do
    name
    |> String.downcase()
    |> String.trim()
  end

  def get_by_id(id) do
    Repo.get(Hashtag, id)
  end

  def get_by_name(name) do
    Repo.get_by(Hashtag, name: normalize_name(name))
  end

  def get_or_create_by_name(name) do
    changeset = changeset(%Hashtag{}, %{name: name})

    Repo.insert(
      changeset,
      on_conflict: [set: [name: get_field(changeset, :name)]],
      conflict_target: :name,
      returning: true
    )
  end

  def get_or_create_by_names(names) when is_list(names) do
    names = Enum.map(names, &normalize_name/1)
    timestamp = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    structs =
      Enum.map(names, fn name ->
        %Hashtag{}
        |> changeset(%{name: name})
        |> Map.get(:changes)
        |> Map.merge(%{inserted_at: timestamp, updated_at: timestamp})
      end)

    try do
      with {:ok, %{query_op: hashtags}} <-
             Multi.new()
             |> Multi.insert_all(:insert_all_op, Hashtag, structs,
               on_conflict: :nothing,
               conflict_target: :name
             )
             |> Multi.run(:query_op, fn _repo, _changes ->
               {:ok, Repo.all(from(ht in Hashtag, where: ht.name in ^names))}
             end)
             |> Repo.transaction() do
        {:ok, hashtags}
      else
        {:error, _name, value, _changes_so_far} -> {:error, value}
      end
    rescue
      e -> {:error, e}
    end
  end

  def changeset(%Hashtag{} = struct, params) do
    struct
    |> cast(params, [:name])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def unlink(%Object{id: object_id}) do
    with {_, hashtag_ids} <-
           from(hto in "hashtags_objects",
             where: hto.object_id == ^object_id,
             select: hto.hashtag_id
           )
           |> Repo.delete_all(),
         {:ok, unreferenced_count} <- delete_unreferenced(hashtag_ids) do
      {:ok, length(hashtag_ids), unreferenced_count}
    end
  end

  @delete_unreferenced_query """
  DELETE FROM hashtags WHERE id IN
    (SELECT hashtags.id FROM hashtags
      LEFT OUTER JOIN hashtags_objects
        ON hashtags_objects.hashtag_id = hashtags.id
      WHERE hashtags_objects.hashtag_id IS NULL AND hashtags.id = ANY($1));
  """

  def delete_unreferenced(ids) do
    with {:ok, %{num_rows: deleted_count}} <- Repo.query(@delete_unreferenced_query, [ids]) do
      {:ok, deleted_count}
    end
  end

  def get_followers(%Hashtag{id: hashtag_id}) do
    from(hf in HashtagFollow)
    |> where([hf], hf.hashtag_id == ^hashtag_id)
    |> join(:inner, [hf], u in assoc(hf, :user))
    |> select([hf, u], u.id)
    |> Repo.all()
  end

  def get_recipients_for_activity(%Pleroma.Activity{object: %{hashtags: tags}})
      when is_list(tags) do
    tags
    |> Enum.map(&get_followers/1)
    |> List.flatten()
    |> Enum.uniq()
  end

  def get_recipients_for_activity(_activity), do: []

  def search(query, options \\ []) do
    limit = Keyword.get(options, :limit, 20)
    offset = Keyword.get(options, :offset, 0)

    search_terms =
      query
      |> String.downcase()
      |> String.trim()
      |> String.split(~r/\s+/)
      |> Enum.filter(&(&1 != ""))
      |> Enum.map(&String.trim_leading(&1, "#"))
      |> Enum.filter(&(&1 != ""))

    if Enum.empty?(search_terms) do
      []
    else
      # Use PostgreSQL's ANY operator with array for efficient multi-term search
      # This is much more efficient than multiple OR clauses
      search_patterns = Enum.map(search_terms, &"%#{&1}%")

      # Create ranking query that prioritizes exact matches and closer matches
      # Use a subquery to properly handle computed columns in ORDER BY
      base_query =
        from(ht in Hashtag,
          where: fragment("LOWER(?) LIKE ANY(?)", ht.name, ^search_patterns),
          select: %{
            name: ht.name,
            # Ranking: exact matches get highest priority (0)
            # then prefix matches (1), then contains (2)
            match_rank:
              fragment(
                """
                  CASE
                    WHEN LOWER(?) = ANY(?) THEN 0
                    WHEN LOWER(?) LIKE ANY(?) THEN 1
                    ELSE 2
                  END
                """,
                ht.name,
                ^search_terms,
                ht.name,
                ^Enum.map(search_terms, &"#{&1}%")
              ),
            # Secondary sort by name length (shorter names first)
            name_length: fragment("LENGTH(?)", ht.name)
          }
        )

      from(result in subquery(base_query),
        order_by: [
          asc: result.match_rank,
          asc: result.name_length,
          asc: result.name
        ],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()
      |> Enum.map(& &1.name)
    end
  end
end
