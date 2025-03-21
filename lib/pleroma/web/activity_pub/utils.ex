# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Utils do
  alias Ecto.Changeset
  alias Ecto.UUID
  alias Pleroma.Activity
  alias Pleroma.Config
  alias Pleroma.EctoType.ActivityPub.ObjectValidators.ObjectID
  alias Pleroma.Maps
  alias Pleroma.Notification
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.AdminAPI.AccountView
  alias Pleroma.Web.Endpoint
  alias Pleroma.Web.Router.Helpers

  import Ecto.Query
  import Pleroma.Web.Utils.Guards, only: [not_empty_string: 1]

  require Logger
  require Pleroma.Constants

  @supported_object_types [
    "Article",
    "Note",
    "Event",
    "Video",
    "Page",
    "Question",
    "Answer",
    "Audio",
    "Image"
  ]
  @strip_status_report_states ~w(closed resolved)
  @supported_report_states ~w(open closed resolved)
  @valid_visibilities ~w(public unlisted private direct)

  def as_local_public, do: Endpoint.url() <> "/#Public"

  # Some implementations send the actor URI as the actor field, others send the entire actor object,
  # so figure out what the actor's URI is based on what we have.
  def get_ap_id(%{"id" => id} = _), do: id
  def get_ap_id(id), do: id

  def normalize_params(params) do
    Map.put(params, "actor", get_ap_id(params["actor"]))
  end

  @spec determine_explicit_mentions(map()) :: [any]
  def determine_explicit_mentions(%{"tag" => tag}) when is_list(tag) do
    Enum.flat_map(tag, fn
      %{"type" => "Mention", "href" => href} -> [href]
      _ -> []
    end)
  end

  def determine_explicit_mentions(%{"tag" => tag} = object) when is_map(tag) do
    object
    |> Map.put("tag", [tag])
    |> determine_explicit_mentions()
  end

  def determine_explicit_mentions(_), do: []

  @spec label_in_collection?(any(), any()) :: boolean()
  defp label_in_collection?(ap_id, coll) when is_binary(coll), do: ap_id == coll
  defp label_in_collection?(ap_id, coll) when is_list(coll), do: ap_id in coll
  defp label_in_collection?(_, _), do: false

  @spec label_in_message?(String.t(), map()) :: boolean()
  def label_in_message?(label, params),
    do:
      [params["to"], params["cc"], params["bto"], params["bcc"]]
      |> Enum.any?(&label_in_collection?(label, &1))

  @spec unaddressed_message?(map()) :: boolean()
  def unaddressed_message?(params),
    do:
      [params["to"], params["cc"], params["bto"], params["bcc"]]
      |> Enum.all?(&is_nil(&1))

  @spec recipient_in_message(User.t(), User.t(), map()) :: boolean()
  def recipient_in_message(%User{ap_id: ap_id} = recipient, %User{} = actor, params),
    do:
      label_in_message?(ap_id, params) || unaddressed_message?(params) ||
        User.following?(recipient, actor)

  defp extract_list(target) when is_binary(target), do: [target]
  defp extract_list(lst) when is_list(lst), do: lst
  defp extract_list(_), do: []

  def maybe_splice_recipient(ap_id, params) do
    need_splice? =
      !label_in_collection?(ap_id, params["to"]) &&
        !label_in_collection?(ap_id, params["cc"])

    if need_splice? do
      cc = [ap_id | extract_list(params["cc"])]

      params
      |> Map.put("cc", cc)
      |> Maps.safe_put_in(["object", "cc"], cc)
    else
      params
    end
  end

  def make_json_ld_header(data \\ %{}) do
    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "#{Endpoint.url()}/schemas/litepub-0.1.jsonld",
        %{
          "@language" => get_language(data)
        }
      ]
    }
  end

  defp get_language(%{"language" => language}) when not_empty_string(language) do
    language
  end

  defp get_language(_), do: "und"

  def make_date do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  def generate_activity_id do
    generate_id("activities")
  end

  def generate_context_id do
    generate_id("contexts")
  end

  def generate_object_id do
    Helpers.o_status_url(Endpoint, :object, UUID.generate())
  end

  def generate_id(type) do
    "#{Endpoint.url()}/#{type}/#{UUID.generate()}"
  end

  def get_notified_from_object(%{"type" => type} = object) when type in @supported_object_types do
    fake_create_activity = %{
      "to" => object["to"],
      "cc" => object["cc"],
      "type" => "Create",
      "object" => object
    }

    get_notified_from_object(fake_create_activity)
  end

  def get_notified_from_object(object) do
    Notification.get_notified_from_activity(%Activity{data: object}, false)
  end

  def maybe_create_context(context), do: context || generate_id("contexts")

  @doc """
  Enqueues an activity for federation if it's local
  """
  @spec maybe_federate(any()) :: :ok
  def maybe_federate(%Activity{local: true, data: %{"type" => type}} = activity) do
    outgoing_blocks = Config.get([:activitypub, :outgoing_blocks])

    with true <- Config.get!([:instance, :federating]),
         true <- type != "Block" || outgoing_blocks,
         false <- Visibility.local_public?(activity) do
      Pleroma.Web.Federator.publish(activity)
    end

    :ok
  end

  def maybe_federate(_), do: :ok

  @doc """
  Adds an id and a published data if they aren't there,
  also adds it to an included object
  """
  @spec lazy_put_activity_defaults(map(), boolean) :: map()
  def lazy_put_activity_defaults(map, fake? \\ false)

  def lazy_put_activity_defaults(map, true) do
    map
    |> Map.put_new("id", "pleroma:fakeid")
    |> Map.put_new_lazy("published", &make_date/0)
    |> Map.put_new("context", "pleroma:fakecontext")
    |> lazy_put_object_defaults(true)
  end

  def lazy_put_activity_defaults(map, _fake?) do
    context = maybe_create_context(map["context"])

    map
    |> Map.put_new_lazy("id", &generate_activity_id/0)
    |> Map.put_new_lazy("published", &make_date/0)
    |> Map.put_new("context", context)
    |> lazy_put_object_defaults(false)
  end

  # Adds an id and published date if they aren't there.
  #
  @spec lazy_put_object_defaults(map(), boolean()) :: map()
  defp lazy_put_object_defaults(%{"object" => map} = activity, true)
       when is_map(map) do
    object =
      map
      |> Map.put_new("id", "pleroma:fake_object_id")
      |> Map.put_new_lazy("published", &make_date/0)
      |> Map.put_new("context", activity["context"])
      |> Map.put_new("fake", true)

    %{activity | "object" => object}
  end

  defp lazy_put_object_defaults(%{"object" => map} = activity, _)
       when is_map(map) do
    object =
      map
      |> Map.put_new_lazy("id", &generate_object_id/0)
      |> Map.put_new_lazy("published", &make_date/0)
      |> Map.put_new("context", activity["context"])

    %{activity | "object" => object}
  end

  defp lazy_put_object_defaults(activity, _), do: activity

  @doc """
  Inserts a full object if it is contained in an activity.
  """
  def insert_full_object(%{"object" => %{"type" => type} = object_data} = map)
      when type in @supported_object_types do
    with {:ok, object} <- Object.create(object_data) do
      map = Map.put(map, "object", object.data["id"])

      {:ok, map, object}
    end
  end

  def insert_full_object(map), do: {:ok, map, nil}

  #### Like-related helpers

  @doc """
  Returns an existing like if a user already liked an object
  """
  @spec get_existing_like(String.t(), map()) :: Activity.t() | nil
  def get_existing_like(actor, %{data: %{"id" => id}}) do
    actor
    |> Activity.Queries.by_actor()
    |> Activity.Queries.by_object_id(id)
    |> Activity.Queries.by_type("Like")
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns like activities targeting an object
  """
  def get_object_likes(%{data: %{"id" => id}}) do
    id
    |> Activity.Queries.by_object_id()
    |> Activity.Queries.by_type("Like")
    |> Repo.all()
  end

  @spec make_like_data(User.t(), map(), String.t()) :: map()
  def make_like_data(
        %User{ap_id: ap_id} = actor,
        %{data: %{"actor" => object_actor_id, "id" => id}} = object,
        activity_id
      ) do
    object_actor = User.get_cached_by_ap_id(object_actor_id)

    to =
      if Visibility.public?(object) do
        [actor.follower_address, object.data["actor"]]
      else
        [object.data["actor"]]
      end

    cc =
      (object.data["to"] ++ (object.data["cc"] || []))
      |> List.delete(actor.ap_id)
      |> List.delete(object_actor.follower_address)

    %{
      "type" => "Like",
      "actor" => ap_id,
      "object" => id,
      "to" => to,
      "cc" => cc,
      "context" => object.data["context"]
    }
    |> Maps.put_if_present("id", activity_id)
  end

  def make_emoji_reaction_data(user, object, emoji, activity_id) do
    make_like_data(user, object, activity_id)
    |> Map.put("type", "EmojiReact")
    |> Map.put("content", emoji)
  end

  @spec update_element_in_object(String.t(), list(any), Object.t(), integer() | nil) ::
          {:ok, Object.t()} | {:error, Ecto.Changeset.t()}
  def update_element_in_object(property, element, object, count \\ nil) do
    length =
      count ||
        length(element)

    data =
      Map.merge(
        object.data,
        %{"#{property}_count" => length, "#{property}s" => element}
      )

    object
    |> Changeset.change(data: data)
    |> Object.update_and_set_cache()
  end

  @spec add_emoji_reaction_to_object(Activity.t(), Object.t()) ::
          {:ok, Object.t()} | {:error, Ecto.Changeset.t()}

  def add_emoji_reaction_to_object(
        %Activity{data: %{"content" => emoji, "actor" => actor}} = activity,
        object
      ) do
    reactions = get_cached_emoji_reactions(object)
    emoji = Pleroma.Emoji.maybe_strip_name(emoji)
    url = maybe_emoji_url(emoji, activity)

    new_reactions =
      case Enum.find_index(reactions, fn [candidate, _, candidate_url] ->
             if is_nil(candidate_url) do
               emoji == candidate
             else
               url == candidate_url
             end
           end) do
        nil ->
          reactions ++ [[emoji, [actor], url]]

        index ->
          List.update_at(
            reactions,
            index,
            fn [emoji, users, url] -> [emoji, Enum.uniq([actor | users]), url] end
          )
      end

    count = emoji_count(new_reactions)

    update_element_in_object("reaction", new_reactions, object, count)
  end

  defp maybe_emoji_url(
         name,
         %Activity{
           data: %{
             "tag" => [
               %{"type" => "Emoji", "name" => name, "icon" => %{"url" => url}}
             ]
           }
         }
       ),
       do: url

  defp maybe_emoji_url(_, _), do: nil

  def emoji_count(reactions_list) do
    Enum.reduce(reactions_list, 0, fn [_, users, _], acc -> acc + length(users) end)
  end

  def remove_emoji_reaction_from_object(
        %Activity{data: %{"content" => emoji, "actor" => actor}} = activity,
        object
      ) do
    emoji = Pleroma.Emoji.maybe_strip_name(emoji)
    reactions = get_cached_emoji_reactions(object)
    url = maybe_emoji_url(emoji, activity)

    new_reactions =
      case Enum.find_index(reactions, fn [candidate, _, candidate_url] ->
             if is_nil(candidate_url) do
               emoji == candidate
             else
               url == candidate_url
             end
           end) do
        nil ->
          reactions

        index ->
          List.update_at(
            reactions,
            index,
            fn [emoji, users, url] -> [emoji, List.delete(users, actor), url] end
          )
          |> Enum.reject(fn [_, users, _] -> Enum.empty?(users) end)
      end

    count = emoji_count(new_reactions)
    update_element_in_object("reaction", new_reactions, object, count)
  end

  def get_cached_emoji_reactions(object) do
    Object.get_emoji_reactions(object)
  end

  @spec add_like_to_object(Activity.t(), Object.t()) ::
          {:ok, Object.t()} | {:error, Ecto.Changeset.t()}
  def add_like_to_object(%Activity{data: %{"actor" => actor}}, object) do
    [actor | fetch_likes(object)]
    |> Enum.uniq()
    |> update_likes_in_object(object)
  end

  @spec remove_like_from_object(Activity.t(), Object.t()) ::
          {:ok, Object.t()} | {:error, Ecto.Changeset.t()}
  def remove_like_from_object(%Activity{data: %{"actor" => actor}}, object) do
    object
    |> fetch_likes()
    |> List.delete(actor)
    |> update_likes_in_object(object)
  end

  defp update_likes_in_object(likes, object) do
    update_element_in_object("like", likes, object)
  end

  defp fetch_likes(object) do
    if is_list(object.data["likes"]) do
      object.data["likes"]
    else
      []
    end
  end

  #### Follow-related helpers

  @doc """
  Updates a follow activity's state (for locked accounts).
  """
  @spec update_follow_state_for_all(Activity.t(), String.t()) :: {:ok, Activity | nil}
  def update_follow_state_for_all(
        %Activity{data: %{"actor" => actor, "object" => object}} = activity,
        state
      ) do
    "Follow"
    |> Activity.Queries.by_type()
    |> Activity.Queries.by_actor(actor)
    |> Activity.Queries.by_object_id(object)
    |> where(fragment("data->>'state' = 'pending'") or fragment("data->>'state' = 'accept'"))
    |> update(set: [data: fragment("jsonb_set(data, '{state}', ?)", ^state)])
    |> Repo.update_all([])

    activity = Activity.get_by_id(activity.id)

    {:ok, activity}
  end

  def update_follow_state(
        %Activity{} = activity,
        state
      ) do
    new_data = Map.put(activity.data, "state", state)
    changeset = Changeset.change(activity, data: new_data)

    with {:ok, activity} <- Repo.update(changeset) do
      {:ok, activity}
    end
  end

  @doc """
  Makes a follow activity data for the given follower and followed
  """
  def make_follow_data(
        %User{ap_id: follower_id},
        %User{ap_id: followed_id} = _followed,
        activity_id
      ) do
    %{
      "type" => "Follow",
      "actor" => follower_id,
      "to" => [followed_id],
      "cc" => [Pleroma.Constants.as_public()],
      "object" => followed_id,
      "state" => "pending"
    }
    |> Maps.put_if_present("id", activity_id)
  end

  def fetch_latest_follow(%User{ap_id: follower_id}, %User{ap_id: followed_id}) do
    "Follow"
    |> Activity.Queries.by_type()
    |> where(actor: ^follower_id)
    # this is to use the index
    |> Activity.Queries.by_object_id(followed_id)
    |> order_by([activity], fragment("? desc nulls last", activity.id))
    |> limit(1)
    |> Repo.one()
  end

  def fetch_latest_undo(%User{ap_id: ap_id}) do
    "Undo"
    |> Activity.Queries.by_type()
    |> where(actor: ^ap_id)
    |> order_by([activity], fragment("? desc nulls last", activity.id))
    |> limit(1)
    |> Repo.one()
  end

  def get_latest_reaction(internal_activity_id, %{ap_id: ap_id}, emoji) do
    %{data: %{"object" => object_ap_id}} = Activity.get_by_id(internal_activity_id)
    emoji = Pleroma.Emoji.maybe_quote(emoji)

    "EmojiReact"
    |> Activity.Queries.by_type()
    |> where(actor: ^ap_id)
    |> custom_emoji_discriminator(emoji)
    |> Activity.Queries.by_object_id(object_ap_id)
    |> order_by([activity], fragment("? desc nulls last", activity.id))
    |> limit(1)
    |> Repo.one()
  end

  defp custom_emoji_discriminator(query, emoji) do
    if String.contains?(emoji, "@") do
      stripped = Pleroma.Emoji.maybe_strip_name(emoji)
      [name, domain] = String.split(stripped, "@")
      domain_pattern = "%/" <> domain <> "/%"
      emoji_pattern = Pleroma.Emoji.maybe_quote(name)

      query
      |> where([activity], fragment("?->>'content' = ?
        AND EXISTS (
          SELECT FROM jsonb_array_elements(?->'tag') elem
          WHERE elem->>'id' ILIKE ?
        )", activity.data, ^emoji_pattern, activity.data, ^domain_pattern))
    else
      query
      |> where([activity], fragment("?->>'content' = ?", activity.data, ^emoji))
    end
  end

  #### Announce-related helpers

  @doc """
  Returns an existing announce activity if the notice has already been announced
  """
  @spec get_existing_announce(String.t(), map()) :: Activity.t() | nil
  def get_existing_announce(actor, %{data: %{"id" => ap_id}}) do
    "Announce"
    |> Activity.Queries.by_type()
    |> where(actor: ^actor)
    # this is to use the index
    |> Activity.Queries.by_object_id(ap_id)
    |> Repo.one()
  end

  @doc """
  Make announce activity data for the given actor and object
  """
  # for relayed messages, we only want to send to subscribers
  def make_announce_data(
        %User{ap_id: ap_id} = user,
        %Object{data: %{"id" => id}} = object,
        activity_id,
        false
      ) do
    %{
      "type" => "Announce",
      "actor" => ap_id,
      "object" => id,
      "to" => [user.follower_address],
      "cc" => [],
      "context" => object.data["context"]
    }
    |> Maps.put_if_present("id", activity_id)
  end

  def make_announce_data(
        %User{ap_id: ap_id} = user,
        %Object{data: %{"id" => id}} = object,
        activity_id,
        true
      ) do
    %{
      "type" => "Announce",
      "actor" => ap_id,
      "object" => id,
      "to" => [user.follower_address, object.data["actor"]],
      "cc" => [Pleroma.Constants.as_public()],
      "context" => object.data["context"]
    }
    |> Maps.put_if_present("id", activity_id)
  end

  def make_undo_data(
        %User{ap_id: actor, follower_address: follower_address},
        %Activity{
          data: %{"id" => undone_activity_id, "context" => context},
          actor: undone_activity_actor
        },
        activity_id \\ nil
      ) do
    %{
      "type" => "Undo",
      "actor" => actor,
      "object" => undone_activity_id,
      "to" => [follower_address, undone_activity_actor],
      "cc" => [Pleroma.Constants.as_public()],
      "context" => context
    }
    |> Maps.put_if_present("id", activity_id)
  end

  @spec add_announce_to_object(Activity.t(), Object.t()) ::
          {:ok, Object.t()} | {:error, Ecto.Changeset.t()}
  def add_announce_to_object(
        %Activity{data: %{"actor" => actor}},
        object
      ) do
    unless actor |> User.get_cached_by_ap_id() |> User.invisible?() do
      announcements = take_announcements(object)

      with announcements <- Enum.uniq([actor | announcements]) do
        update_element_in_object("announcement", announcements, object)
      end
    else
      {:ok, object}
    end
  end

  def add_announce_to_object(_, object), do: {:ok, object}

  @spec remove_announce_from_object(Activity.t(), Object.t()) ::
          {:ok, Object.t()} | {:error, Ecto.Changeset.t()}
  def remove_announce_from_object(%Activity{data: %{"actor" => actor}}, object) do
    with announcements <- List.delete(take_announcements(object), actor) do
      update_element_in_object("announcement", announcements, object)
    end
  end

  defp take_announcements(%{data: %{"announcements" => announcements}} = _)
       when is_list(announcements),
       do: announcements

  defp take_announcements(_), do: []

  #### Unfollow-related helpers

  def make_unfollow_data(follower, followed, follow_activity, activity_id) do
    %{
      "type" => "Undo",
      "actor" => follower.ap_id,
      "to" => [followed.ap_id],
      "object" => follow_activity.data
    }
    |> Maps.put_if_present("id", activity_id)
  end

  #### Block-related helpers
  @spec fetch_latest_block(User.t(), User.t()) :: Activity.t() | nil
  def fetch_latest_block(%User{ap_id: blocker_id}, %User{ap_id: blocked_id}) do
    "Block"
    |> Activity.Queries.by_type()
    |> where(actor: ^blocker_id)
    # this is to use the index
    |> Activity.Queries.by_object_id(blocked_id)
    |> order_by([activity], fragment("? desc nulls last", activity.id))
    |> limit(1)
    |> Repo.one()
  end

  def make_block_data(blocker, blocked, activity_id) do
    %{
      "type" => "Block",
      "actor" => blocker.ap_id,
      "to" => [blocked.ap_id],
      "object" => blocked.ap_id
    }
    |> Maps.put_if_present("id", activity_id)
  end

  #### Create-related helpers

  def make_create_data(params, additional) do
    published = params.published || make_date()

    %{
      "type" => "Create",
      "to" => params.to |> Enum.uniq(),
      "actor" => params.actor.ap_id,
      "object" => params.object,
      "published" => published,
      "context" => params.context
    }
    |> Map.merge(additional)
  end

  #### Listen-related helpers
  def make_listen_data(params, additional) do
    published = params.published || make_date()

    %{
      "type" => "Listen",
      "to" => params.to |> Enum.uniq(),
      "actor" => params.actor.ap_id,
      "object" => params.object,
      "published" => published,
      "context" => params.context
    }
    |> Map.merge(additional)
  end

  #### Flag-related helpers
  @spec make_flag_data(map(), map()) :: map()
  def make_flag_data(
        %{actor: actor, context: context, content: content} = params,
        additional
      ) do
    %{
      "type" => "Flag",
      "actor" => actor.ap_id,
      "content" => content,
      "object" => build_flag_object(params),
      "context" => context,
      "state" => "open",
      "rules" => Map.get(params, :rules, nil)
    }
    |> Map.merge(additional)
  end

  def make_flag_data(_, _), do: %{}

  defp build_flag_object(%{account: account, statuses: statuses}) do
    [account.ap_id | build_flag_object(%{statuses: statuses})]
  end

  defp build_flag_object(%{statuses: statuses}) do
    Enum.map(statuses || [], &build_flag_object/1)
  end

  defp build_flag_object(%Activity{} = activity) do
    object = Object.normalize(activity, fetch: false)

    # Do not allow people to report Creates. Instead, report the Object that is Created.
    if activity.data["type"] != "Create" do
      build_flag_object_with_actor_and_id(
        object,
        User.get_by_ap_id(activity.data["actor"]),
        activity.data["id"]
      )
    else
      build_flag_object(object)
    end
  end

  defp build_flag_object(%Object{} = object) do
    actor = User.get_by_ap_id(object.data["actor"])
    build_flag_object_with_actor_and_id(object, actor, object.data["id"])
  end

  defp build_flag_object(act) when is_map(act) or is_binary(act) do
    id =
      case act do
        %Activity{} = act -> act.data["id"]
        act when is_map(act) -> act["id"]
        act when is_binary(act) -> act
      end

    case Activity.get_by_ap_id_with_object(id) do
      %Activity{object: object} = _ ->
        build_flag_object(object)

      nil ->
        case Object.get_by_ap_id(id) do
          %Object{} = object -> build_flag_object(object)
          _ -> %{"id" => id, "deleted" => true}
        end
    end
  end

  defp build_flag_object(_), do: []

  defp build_flag_object_with_actor_and_id(%Object{data: data}, actor, id) do
    %{
      "type" => "Note",
      "id" => id,
      "content" => data["content"],
      "published" => data["published"],
      "actor" =>
        AccountView.render(
          "show.json",
          %{user: actor, skip_visibility_check: true}
        )
    }
  end

  #### Report-related helpers
  def get_reports(params, page, page_size) do
    params =
      params
      |> Map.put(:type, "Flag")
      |> Map.put(:skip_preload, true)
      |> Map.put(:preload_report_notes, true)
      |> Map.put(:total, true)
      |> Map.put(:limit, page_size)
      |> Map.put(:offset, (page - 1) * page_size)

    ActivityPub.fetch_activities([], params, :offset)
  end

  defp maybe_strip_report_status(data, state) do
    with true <- Config.get([:instance, :report_strip_status]),
         true <- state in @strip_status_report_states,
         {:ok, stripped_activity} = strip_report_status_data(%Activity{data: data}) do
      data |> Map.put("object", stripped_activity.data["object"])
    else
      _ -> data
    end
  end

  def update_report_state(%Activity{} = activity, state) when state in @supported_report_states do
    new_data =
      activity.data
      |> Map.put("state", state)
      |> maybe_strip_report_status(state)

    activity
    |> Changeset.change(data: new_data)
    |> Repo.update()
  end

  def update_report_state(activity_ids, state) when state in @supported_report_states do
    activities_num = length(activity_ids)

    from(a in Activity, where: a.id in ^activity_ids)
    |> update(set: [data: fragment("jsonb_set(data, '{state}', ?)", ^state)])
    |> Repo.update_all([])
    |> case do
      {^activities_num, _} -> :ok
      _ -> {:error, activity_ids}
    end
  end

  def update_report_state(_, _), do: {:error, "Unsupported state"}

  def strip_report_status_data(activity) do
    [actor | reported_activities] = activity.data["object"]

    stripped_activities =
      Enum.reduce(reported_activities, [], fn act, acc ->
        case ObjectID.cast(act) do
          {:ok, act} -> [act | acc]
          _ -> acc
        end
      end)

    new_data = put_in(activity.data, ["object"], [actor | stripped_activities])

    {:ok, %{activity | data: new_data}}
  end

  def update_activity_visibility(activity, visibility) when visibility in @valid_visibilities do
    [to, cc, recipients] =
      activity
      |> get_updated_targets(visibility)
      |> Enum.map(&Enum.uniq/1)

    object_data =
      activity.object.data
      |> Map.put("to", to)
      |> Map.put("cc", cc)

    {:ok, object} =
      activity.object
      |> Object.change(%{data: object_data})
      |> Object.update_and_set_cache()

    activity_data =
      activity.data
      |> Map.put("to", to)
      |> Map.put("cc", cc)

    activity
    |> Map.put(:object, object)
    |> Activity.change(%{data: activity_data, recipients: recipients})
    |> Repo.update()
  end

  def update_activity_visibility(_, _), do: {:error, "Unsupported visibility"}

  defp get_updated_targets(
         %Activity{data: %{"to" => to} = data, recipients: recipients},
         visibility
       ) do
    cc = Map.get(data, "cc", [])
    follower_address = User.get_cached_by_ap_id(data["actor"]).follower_address
    public = Pleroma.Constants.as_public()

    case visibility do
      "public" ->
        to = [public | List.delete(to, follower_address)]
        cc = [follower_address | List.delete(cc, public)]
        recipients = [public | recipients]
        [to, cc, recipients]

      "private" ->
        to = [follower_address | List.delete(to, public)]
        cc = List.delete(cc, public)
        recipients = List.delete(recipients, public)
        [to, cc, recipients]

      "unlisted" ->
        to = [follower_address | List.delete(to, public)]
        cc = [public | List.delete(cc, follower_address)]
        recipients = recipients ++ [follower_address, public]
        [to, cc, recipients]

      _ ->
        [to, cc, recipients]
    end
  end

  def get_existing_votes(actor, %{data: %{"id" => id}}) do
    actor
    |> Activity.Queries.by_actor()
    |> Activity.Queries.by_type("Create")
    |> Activity.with_preloaded_object()
    |> where([a, object: o], fragment("(?)->>'inReplyTo' = ?", o.data, ^to_string(id)))
    |> where([a, object: o], fragment("(?)->>'type' = 'Answer'", o.data))
    |> Repo.all()
  end

  @spec maybe_handle_group_posts(Activity.t()) :: :ok
  @doc "Automatically repeats posts for local group actor recipients"
  def maybe_handle_group_posts(activity) do
    poster = User.get_cached_by_ap_id(activity.actor)

    User.get_recipients_from_activity(activity)
    |> Enum.filter(&match?("Group", &1.actor_type))
    |> Enum.reject(&User.blocks?(&1, poster))
    |> Enum.each(&Pleroma.Web.CommonAPI.repeat(activity.id, &1))
  end
end
