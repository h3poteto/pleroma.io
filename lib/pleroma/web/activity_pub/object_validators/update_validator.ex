# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.UpdateValidator do
  use Ecto.Schema

  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Object
  alias Pleroma.User

  import Ecto.Changeset
  import Pleroma.Web.ActivityPub.ObjectValidators.CommonValidations

  @primary_key false

  embedded_schema do
    quote do
      unquote do
        import Elixir.Pleroma.Web.ActivityPub.ObjectValidators.CommonFields
        message_fields()
      end
    end

    field(:actor, ObjectValidators.ObjectID)
    # In this case, we save the full object in this activity instead of just a
    # reference, so we can always see what was actually changed by this.
    field(:object, :map)
  end

  def cast_data(data) do
    %__MODULE__{}
    |> cast(data, __schema__(:fields))
  end

  defp validate_data(cng, meta) do
    cng
    |> validate_required([:id, :type, :actor, :to, :cc, :object])
    |> validate_inclusion(:type, ["Update"])
    |> validate_actor_presence()
    |> validate_updating_rights(meta)
  end

  def cast_and_validate(data, meta \\ []) do
    data
    |> cast_data
    |> validate_data(meta)
  end

  def validate_updating_rights(cng, meta) do
    if meta[:local] do
      validate_updating_rights_local(cng)
    else
      validate_updating_rights_remote(cng)
    end
  end

  # For local Updates, verify the actor can edit the object
  def validate_updating_rights_local(cng) do
    actor = get_field(cng, :actor)
    updated_object = get_field(cng, :object)

    if {:ok, actor} == ObjectValidators.ObjectID.cast(updated_object) do
      cng
    else
      with %User{} = user <- User.get_cached_by_ap_id(actor),
           {_, %Object{} = orig_object} <- {:object, Object.normalize(updated_object)},
           :ok <- Object.authorize_access(orig_object, user) do
        cng
      else
        _e ->
          cng
          |> add_error(:object, "Can't be updated by this actor")
      end
    end
  end

  # For remote Updates, verify the host is the same.
  def validate_updating_rights_remote(cng) do
    with actor = get_field(cng, :actor),
         object = get_field(cng, :object),
         {:ok, object_id} <- ObjectValidators.ObjectID.cast(object),
         actor_uri <- URI.parse(actor),
         object_uri <- URI.parse(object_id),
         true <- actor_uri.host == object_uri.host do
      cng
    else
      _e ->
        cng
        |> add_error(:object, "Can't be updated by this actor")
    end
  end
end
