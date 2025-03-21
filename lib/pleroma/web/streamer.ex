# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Streamer do
  require Logger
  require Pleroma.Constants

  alias Pleroma.Activity
  alias Pleroma.Chat.MessageReference
  alias Pleroma.Config
  alias Pleroma.Conversation.Participation
  alias Pleroma.Notification
  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.OAuth.Token
  alias Pleroma.Web.Plugs.OAuthScopesPlug
  alias Pleroma.Web.StreamerView
  require Pleroma.Constants

  @registry Pleroma.Web.StreamerRegistry

  def registry, do: @registry

  @public_streams Pleroma.Constants.public_streams()
  @local_streams ["public:local", "public:local:media"]
  @user_streams ["user", "user:notification", "direct", "user:pleroma_chat"]

  @doc "Expands and authorizes a stream, and registers the process for streaming."
  @spec get_topic_and_add_socket(
          stream :: String.t(),
          User.t() | nil,
          Token.t() | nil,
          map() | nil
        ) ::
          {:ok, topic :: String.t()} | {:error, :bad_topic} | {:error, :unauthorized}
  def get_topic_and_add_socket(stream, user, oauth_token, params \\ %{}) do
    with {:ok, topic} <- get_topic(stream, user, oauth_token, params) do
      add_socket(topic, oauth_token)
    end
  end

  defp can_access_stream(user, oauth_token, kind) do
    with {_, true} <- {:restrict?, Config.restrict_unauthenticated_access?(:timelines, kind)},
         {_, %User{id: user_id}, %Token{user_id: user_id}} <- {:user, user, oauth_token},
         {_, true} <-
           {:scopes,
            OAuthScopesPlug.filter_descendants(["read:statuses"], oauth_token.scopes) != []} do
      true
    else
      {:restrict?, _} ->
        true

      _ ->
        false
    end
  end

  @doc "Expand and authorizes a stream"
  @spec get_topic(stream :: String.t() | nil, User.t() | nil, Token.t() | nil, map()) ::
          {:ok, topic :: String.t() | nil} | {:error, :bad_topic}
  def get_topic(stream, user, oauth_token, params \\ %{})

  def get_topic(nil = _stream, _user, _oauth_token, _params) do
    {:ok, nil}
  end

  # Allow all public steams if the instance allows unauthenticated access.
  # Otherwise, only allow users with valid oauth tokens.
  def get_topic(stream, user, oauth_token, _params) when stream in @public_streams do
    kind = if stream in @local_streams, do: :local, else: :federated

    if can_access_stream(user, oauth_token, kind) do
      {:ok, stream}
    else
      {:error, :unauthorized}
    end
  end

  # Allow all hashtags streams.
  def get_topic("hashtag", _user, _oauth_token, %{"tag" => tag} = _params) do
    {:ok, "hashtag:" <> tag}
  end

  # Allow remote instance streams.
  def get_topic("public:remote", user, oauth_token, %{"instance" => instance} = _params) do
    if can_access_stream(user, oauth_token, :federated) do
      {:ok, "public:remote:" <> instance}
    else
      {:error, :unauthorized}
    end
  end

  def get_topic("public:remote:media", user, oauth_token, %{"instance" => instance} = _params) do
    if can_access_stream(user, oauth_token, :federated) do
      {:ok, "public:remote:media:" <> instance}
    else
      {:error, :unauthorized}
    end
  end

  # Expand user streams.
  def get_topic(
        stream,
        %User{id: user_id} = user,
        %Token{user_id: user_id} = oauth_token,
        _params
      )
      when stream in @user_streams do
    # Note: "read" works for all user streams (not mentioning it since it's an ancestor scope)
    required_scopes =
      if stream == "user:notification" do
        ["read:notifications"]
      else
        ["read:statuses"]
      end

    if OAuthScopesPlug.filter_descendants(required_scopes, oauth_token.scopes) == [] do
      {:error, :unauthorized}
    else
      {:ok, stream <> ":" <> to_string(user.id)}
    end
  end

  def get_topic(stream, _user, _oauth_token, _params) when stream in @user_streams do
    {:error, :unauthorized}
  end

  # List streams.
  def get_topic(
        "list",
        %User{id: user_id} = user,
        %Token{user_id: user_id} = oauth_token,
        %{"list" => id}
      ) do
    cond do
      OAuthScopesPlug.filter_descendants(["read", "read:lists"], oauth_token.scopes) == [] ->
        {:error, :unauthorized}

      Pleroma.List.get(id, user) ->
        {:ok, "list:" <> to_string(id)}

      true ->
        {:error, :bad_topic}
    end
  end

  def get_topic("list", _user, _oauth_token, _params) do
    {:error, :unauthorized}
  end

  def get_topic(_stream, _user, _oauth_token, _params) do
    {:error, :bad_topic}
  end

  @doc "Registers the process for streaming. Use `get_topic/3` to get the full authorized topic."
  def add_socket(topic, oauth_token) do
    if should_env_send?() do
      oauth_token_id = if oauth_token, do: oauth_token.id, else: false
      Registry.register(@registry, topic, oauth_token_id)
    end

    {:ok, topic}
  end

  def remove_socket(topic) do
    if should_env_send?(), do: Registry.unregister(@registry, topic)
  end

  def stream(topics, items) do
    if should_env_send?() do
      for topic <- List.wrap(topics), item <- List.wrap(items) do
        fun = fn -> do_stream(topic, item) end

        if Config.get([__MODULE__, :sync_streaming], false) do
          fun.()
        else
          spawn(fun)
        end
      end
    end
  end

  def filtered_by_user?(user, item, streamed_type \\ :activity)

  def filtered_by_user?(%User{} = user, %Activity{} = item, streamed_type) do
    %{block: blocked_ap_ids, mute: muted_ap_ids, reblog_mute: reblog_muted_ap_ids} =
      User.outgoing_relationships_ap_ids(user, [:block, :mute, :reblog_mute])

    recipient_blocks = MapSet.new(blocked_ap_ids ++ muted_ap_ids)
    recipients = MapSet.new(item.recipients)
    domain_blocks = Pleroma.Web.ActivityPub.MRF.subdomains_regex(user.domain_blocks)

    with parent <- Object.normalize(item, fetch: false) || item,
         true <- Enum.all?([blocked_ap_ids, muted_ap_ids], &(item.actor not in &1)),
         true <- item.data["type"] != "Announce" || item.actor not in reblog_muted_ap_ids,
         true <-
           !(streamed_type == :activity && item.data["type"] == "Announce" &&
               parent.data["actor"] == user.ap_id),
         true <- Enum.all?([blocked_ap_ids, muted_ap_ids], &(parent.data["actor"] not in &1)),
         true <- MapSet.disjoint?(recipients, recipient_blocks),
         %{host: item_host} <- URI.parse(item.actor),
         %{host: parent_host} <- URI.parse(parent.data["actor"]),
         false <- Pleroma.Web.ActivityPub.MRF.subdomain_match?(domain_blocks, item_host),
         false <- Pleroma.Web.ActivityPub.MRF.subdomain_match?(domain_blocks, parent_host),
         true <- thread_containment(item, user),
         false <- CommonAPI.thread_muted?(parent, user) do
      false
    else
      _ -> true
    end
  end

  def filtered_by_user?(%User{} = user, %Notification{activity: activity}, _) do
    filtered_by_user?(user, activity, :notification)
  end

  defp do_stream("direct", item) do
    recipient_topics =
      User.get_recipients_from_activity(item)
      |> Enum.map(fn %{id: id} -> "direct:#{id}" end)

    Enum.each(recipient_topics, fn user_topic ->
      Logger.debug("Trying to push direct message to #{user_topic}\n\n")
      push_to_socket(user_topic, item)
    end)
  end

  defp do_stream("follow_relationship", item) do
    user_topic = "user:#{item.follower.id}"
    text = StreamerView.render("follow_relationships_update.json", item, user_topic)

    Logger.debug("Trying to push follow relationship update to #{user_topic}\n\n")

    Registry.dispatch(@registry, user_topic, fn list ->
      Enum.each(list, fn {pid, _auth} ->
        send(pid, {:text, text})
      end)
    end)
  end

  defp do_stream("participation", participation) do
    user_topic = "direct:#{participation.user_id}"
    Logger.debug("Trying to push a conversation participation to #{user_topic}\n\n")

    push_to_socket(user_topic, participation)
  end

  defp do_stream("list", item) do
    # filter the recipient list if the activity is not public, see #270.
    recipient_lists =
      case Visibility.public?(item) do
        true ->
          Pleroma.List.get_lists_from_activity(item)

        _ ->
          Pleroma.List.get_lists_from_activity(item)
          |> Enum.filter(fn list ->
            owner = User.get_cached_by_id(list.user_id)

            Visibility.visible_for_user?(item, owner)
          end)
      end

    recipient_topics =
      recipient_lists
      |> Enum.map(fn %{id: id} -> "list:#{id}" end)

    Enum.each(recipient_topics, fn list_topic ->
      Logger.debug("Trying to push message to #{list_topic}\n\n")
      push_to_socket(list_topic, item)
    end)
  end

  defp do_stream(topic, %Notification{} = item)
       when topic in ["user", "user:notification"] do
    user_topic = "#{topic}:#{item.user_id}"

    Registry.dispatch(@registry, user_topic, fn list ->
      Enum.each(list, fn {pid, _auth} ->
        send(pid, {:render_with_user, StreamerView, "notification.json", item, user_topic})
      end)
    end)
  end

  defp do_stream(topic, {user, %MessageReference{} = cm_ref})
       when topic in ["user", "user:pleroma_chat"] do
    topic = "#{topic}:#{user.id}"

    text = StreamerView.render("chat_update.json", %{chat_message_reference: cm_ref}, topic)

    Registry.dispatch(@registry, topic, fn list ->
      Enum.each(list, fn {pid, _auth} ->
        send(pid, {:text, text})
      end)
    end)
  end

  defp do_stream("user", item) do
    Logger.debug("Trying to push to users")

    recipient_topics =
      User.get_recipients_from_activity(item)
      |> Enum.map(fn %{id: id} -> "user:#{id}" end)

    hashtag_recipients =
      if Pleroma.Constants.as_public() in item.recipients do
        Pleroma.Hashtag.get_recipients_for_activity(item)
        |> Enum.map(fn id -> "user:#{id}" end)
      else
        []
      end

    all_recipients = Enum.uniq(recipient_topics ++ hashtag_recipients)

    Enum.each(all_recipients, fn topic ->
      push_to_socket(topic, item)
    end)
  end

  defp do_stream(topic, item) do
    Logger.debug("Trying to push to #{topic}")
    Logger.debug("Pushing item to #{topic}")
    push_to_socket(topic, item)
  end

  defp push_to_socket(topic, %Participation{} = participation) do
    rendered = StreamerView.render("conversation.json", participation, topic)

    Registry.dispatch(@registry, topic, fn list ->
      Enum.each(list, fn {pid, _} ->
        send(pid, {:text, rendered})
      end)
    end)
  end

  defp push_to_socket(topic, %Activity{
         data: %{"type" => "Delete", "deleted_activity_id" => deleted_activity_id}
       }) do
    rendered = Jason.encode!(%{event: "delete", payload: to_string(deleted_activity_id)})

    Registry.dispatch(@registry, topic, fn list ->
      Enum.each(list, fn {pid, _} ->
        send(pid, {:text, rendered})
      end)
    end)
  end

  defp push_to_socket(_topic, %Activity{data: %{"type" => "Delete"}}), do: :noop

  defp push_to_socket(topic, %Activity{data: %{"type" => "Update"}} = item) do
    create_activity =
      Pleroma.Activity.get_create_by_object_ap_id(item.object.data["id"])
      |> Map.put(:object, item.object)

    anon_render = StreamerView.render("status_update.json", create_activity, topic)

    Registry.dispatch(@registry, topic, fn list ->
      Enum.each(list, fn {pid, auth?} ->
        if auth? do
          send(
            pid,
            {:render_with_user, StreamerView, "status_update.json", create_activity, topic}
          )
        else
          send(pid, {:text, anon_render})
        end
      end)
    end)
  end

  defp push_to_socket(topic, item) do
    anon_render = StreamerView.render("update.json", item, topic)

    Registry.dispatch(@registry, topic, fn list ->
      Enum.each(list, fn {pid, auth?} ->
        if auth? do
          send(pid, {:render_with_user, StreamerView, "update.json", item, topic})
        else
          send(pid, {:text, anon_render})
        end
      end)
    end)
  end

  defp thread_containment(_activity, %User{skip_thread_containment: true}), do: true

  defp thread_containment(activity, user) do
    if Config.get([:instance, :skip_thread_containment]) do
      true
    else
      ActivityPub.contain_activity(activity, user)
    end
  end

  def close_streams_by_oauth_token(oauth_token) do
    if should_env_send?() do
      Registry.select(
        @registry,
        [
          {
            {:"$1", :"$2", :"$3"},
            [{:==, :"$3", oauth_token.id}],
            [:"$2"]
          }
        ]
      )
      |> Enum.each(fn pid -> send(pid, :close) end)
    end
  end

  # In dev/prod the streamer registry is expected to be started, so return true
  # In test it is possible to have the registry started for a test so it will check
  # In benchmark it will never find the process alive and return false
  def should_env_send? do
    if Application.get_env(:pleroma, Pleroma.Application)[:streamer_registry] do
      true
    else
      case Process.whereis(@registry) do
        nil ->
          false

        pid ->
          Process.alive?(pid)
      end
    end
  end
end
