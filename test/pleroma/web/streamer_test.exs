# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.StreamerTest do
  use Pleroma.DataCase

  import Pleroma.Factory

  alias Pleroma.Chat
  alias Pleroma.Chat.MessageReference
  alias Pleroma.Conversation.Participation
  alias Pleroma.List
  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.Streamer
  alias Pleroma.Web.StreamerView

  @moduletag needs_streamer: true, capture_log: true

  setup do: clear_config([:instance, :skip_thread_containment])

  describe "get_topic/_ (unauthenticated)" do
    test "allows no stream" do
      assert {:ok, nil} = Streamer.get_topic(nil, nil, nil)
    end

    test "allows public" do
      assert {:ok, "public"} = Streamer.get_topic("public", nil, nil)
      assert {:ok, "public:local"} = Streamer.get_topic("public:local", nil, nil)
      assert {:ok, "public:media"} = Streamer.get_topic("public:media", nil, nil)
      assert {:ok, "public:local:media"} = Streamer.get_topic("public:local:media", nil, nil)
    end

    test "rejects local public streams if restricted_unauthenticated is on" do
      clear_config([:restrict_unauthenticated, :timelines, :local], true)

      assert {:error, :unauthorized} = Streamer.get_topic("public:local", nil, nil)
      assert {:error, :unauthorized} = Streamer.get_topic("public:local:media", nil, nil)
    end

    test "rejects remote public streams if restricted_unauthenticated is on" do
      clear_config([:restrict_unauthenticated, :timelines, :federated], true)

      assert {:error, :unauthorized} = Streamer.get_topic("public", nil, nil)
      assert {:error, :unauthorized} = Streamer.get_topic("public:media", nil, nil)

      assert {:error, :unauthorized} =
               Streamer.get_topic("public:remote", nil, nil, %{"instance" => "lain.com"})

      assert {:error, :unauthorized} =
               Streamer.get_topic("public:remote:media", nil, nil, %{"instance" => "lain.com"})
    end

    test "allows instance streams" do
      assert {:ok, "public:remote:lain.com"} =
               Streamer.get_topic("public:remote", nil, nil, %{"instance" => "lain.com"})

      assert {:ok, "public:remote:media:lain.com"} =
               Streamer.get_topic("public:remote:media", nil, nil, %{"instance" => "lain.com"})
    end

    test "allows hashtag streams" do
      assert {:ok, "hashtag:cofe"} = Streamer.get_topic("hashtag", nil, nil, %{"tag" => "cofe"})
    end

    test "disallows user streams" do
      assert {:error, _} = Streamer.get_topic("user", nil, nil)
      assert {:error, _} = Streamer.get_topic("user:notification", nil, nil)
      assert {:error, _} = Streamer.get_topic("direct", nil, nil)
    end

    test "disallows list streams" do
      assert {:error, _} = Streamer.get_topic("list", nil, nil, %{"list" => 42})
    end
  end

  describe "get_topic/_ (authenticated)" do
    setup do: oauth_access(["read"])

    test "allows public streams (regardless of OAuth token scopes)", %{
      user: user,
      token: read_oauth_token
    } do
      with oauth_token <- [nil, read_oauth_token] do
        assert {:ok, "public"} = Streamer.get_topic("public", user, oauth_token)
        assert {:ok, "public:local"} = Streamer.get_topic("public:local", user, oauth_token)
        assert {:ok, "public:media"} = Streamer.get_topic("public:media", user, oauth_token)

        assert {:ok, "public:local:media"} =
                 Streamer.get_topic("public:local:media", user, oauth_token)
      end
    end

    test "allows local public streams if restricted_unauthenticated is on", %{
      user: user,
      token: oauth_token
    } do
      clear_config([:restrict_unauthenticated, :timelines, :local], true)

      %{token: read_notifications_token} = oauth_access(["read:notifications"], user: user)
      %{token: badly_scoped_token} = oauth_access(["irrelevant:scope"], user: user)

      assert {:ok, "public:local"} = Streamer.get_topic("public:local", user, oauth_token)

      assert {:ok, "public:local:media"} =
               Streamer.get_topic("public:local:media", user, oauth_token)

      for token <- [read_notifications_token, badly_scoped_token] do
        assert {:error, :unauthorized} = Streamer.get_topic("public:local", user, token)

        assert {:error, :unauthorized} = Streamer.get_topic("public:local:media", user, token)
      end
    end

    test "allows remote public streams if restricted_unauthenticated is on", %{
      user: user,
      token: oauth_token
    } do
      clear_config([:restrict_unauthenticated, :timelines, :federated], true)

      %{token: read_notifications_token} = oauth_access(["read:notifications"], user: user)
      %{token: badly_scoped_token} = oauth_access(["irrelevant:scope"], user: user)

      assert {:ok, "public"} = Streamer.get_topic("public", user, oauth_token)
      assert {:ok, "public:media"} = Streamer.get_topic("public:media", user, oauth_token)

      assert {:ok, "public:remote:lain.com"} =
               Streamer.get_topic("public:remote", user, oauth_token, %{"instance" => "lain.com"})

      assert {:ok, "public:remote:media:lain.com"} =
               Streamer.get_topic("public:remote:media", user, oauth_token, %{
                 "instance" => "lain.com"
               })

      for token <- [read_notifications_token, badly_scoped_token] do
        assert {:error, :unauthorized} = Streamer.get_topic("public", user, token)
        assert {:error, :unauthorized} = Streamer.get_topic("public:media", user, token)

        assert {:error, :unauthorized} =
                 Streamer.get_topic("public:remote", user, token, %{
                   "instance" => "lain.com"
                 })

        assert {:error, :unauthorized} =
                 Streamer.get_topic("public:remote:media", user, token, %{
                   "instance" => "lain.com"
                 })
      end
    end

    test "allows user streams (with proper OAuth token scopes)", %{
      user: user,
      token: read_oauth_token
    } do
      %{token: read_notifications_token} = oauth_access(["read:notifications"], user: user)
      %{token: read_statuses_token} = oauth_access(["read:statuses"], user: user)
      %{token: badly_scoped_token} = oauth_access(["irrelevant:scope"], user: user)

      expected_user_topic = "user:#{user.id}"
      expected_notification_topic = "user:notification:#{user.id}"
      expected_direct_topic = "direct:#{user.id}"
      expected_pleroma_chat_topic = "user:pleroma_chat:#{user.id}"

      for valid_user_token <- [read_oauth_token, read_statuses_token] do
        assert {:ok, ^expected_user_topic} = Streamer.get_topic("user", user, valid_user_token)

        assert {:ok, ^expected_direct_topic} =
                 Streamer.get_topic("direct", user, valid_user_token)

        assert {:ok, ^expected_pleroma_chat_topic} =
                 Streamer.get_topic("user:pleroma_chat", user, valid_user_token)
      end

      for invalid_user_token <- [read_notifications_token, badly_scoped_token],
          user_topic <- ["user", "direct", "user:pleroma_chat"] do
        assert {:error, :unauthorized} = Streamer.get_topic(user_topic, user, invalid_user_token)
      end

      for valid_notification_token <- [read_oauth_token, read_notifications_token] do
        assert {:ok, ^expected_notification_topic} =
                 Streamer.get_topic("user:notification", user, valid_notification_token)
      end

      for invalid_notification_token <- [read_statuses_token, badly_scoped_token] do
        assert {:error, :unauthorized} =
                 Streamer.get_topic("user:notification", user, invalid_notification_token)
      end
    end

    test "allows hashtag streams (regardless of OAuth token scopes)", %{
      user: user,
      token: read_oauth_token
    } do
      for oauth_token <- [nil, read_oauth_token] do
        assert {:ok, "hashtag:cofe"} =
                 Streamer.get_topic("hashtag", user, oauth_token, %{"tag" => "cofe"})
      end
    end

    test "disallows registering to another user's stream", %{user: user, token: read_oauth_token} do
      another_user = insert(:user)
      assert {:error, _} = Streamer.get_topic("user:#{another_user.id}", user, read_oauth_token)

      assert {:error, _} =
               Streamer.get_topic("user:notification:#{another_user.id}", user, read_oauth_token)

      assert {:error, _} = Streamer.get_topic("direct:#{another_user.id}", user, read_oauth_token)
    end

    test "allows list stream that are owned by the user (with `read` or `read:lists` scopes)", %{
      user: user,
      token: read_oauth_token
    } do
      %{token: read_lists_token} = oauth_access(["read:lists"], user: user)
      %{token: invalid_token} = oauth_access(["irrelevant:scope"], user: user)
      {:ok, list} = List.create("Test", user)

      assert {:error, _} = Streamer.get_topic("list:#{list.id}", user, read_oauth_token)

      for valid_token <- [read_oauth_token, read_lists_token] do
        assert {:ok, _} = Streamer.get_topic("list", user, valid_token, %{"list" => list.id})
      end

      assert {:error, _} = Streamer.get_topic("list", user, invalid_token, %{"list" => list.id})
    end

    test "disallows list stream that are not owned by the user", %{user: user, token: oauth_token} do
      another_user = insert(:user)
      {:ok, list} = List.create("Test", another_user)

      assert {:error, _} = Streamer.get_topic("list:#{list.id}", user, oauth_token)
      assert {:error, _} = Streamer.get_topic("list", user, oauth_token, %{"list" => list.id})
    end
  end

  describe "user streams" do
    setup do
      %{user: user, token: token} = oauth_access(["read"])
      notify = insert(:notification, user: user, activity: build(:note_activity))
      {:ok, %{user: user, notify: notify, token: token}}
    end

    test "it streams the user's post in the 'user' stream", %{user: user, token: oauth_token} do
      Streamer.get_topic_and_add_socket("user", user, oauth_token)
      {:ok, activity} = CommonAPI.post(user, %{status: "hey"})

      assert_receive {:render_with_user, _, _, ^activity, _}
      refute Streamer.filtered_by_user?(user, activity)
    end

    test "it streams boosts of the user in the 'user' stream", %{user: user, token: oauth_token} do
      Streamer.get_topic_and_add_socket("user", user, oauth_token)

      other_user = insert(:user)
      {:ok, activity} = CommonAPI.post(other_user, %{status: "hey"})
      {:ok, announce} = CommonAPI.repeat(activity.id, user)

      assert_receive {:render_with_user, Pleroma.Web.StreamerView, "update.json", ^announce, _}
      refute Streamer.filtered_by_user?(user, announce)
    end

    test "it does not stream announces of the user's own posts in the 'user' stream", %{
      user: user,
      token: oauth_token
    } do
      Streamer.get_topic_and_add_socket("user", user, oauth_token)

      other_user = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{status: "hey"})
      {:ok, announce} = CommonAPI.repeat(activity.id, other_user)

      assert Streamer.filtered_by_user?(user, announce)
    end

    test "it does stream notifications announces of the user's own posts in the 'user' stream", %{
      user: user,
      token: oauth_token
    } do
      Streamer.get_topic_and_add_socket("user", user, oauth_token)

      other_user = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{status: "hey"})
      {:ok, announce} = CommonAPI.repeat(activity.id, other_user)

      notification =
        Pleroma.Notification
        |> Repo.get_by(%{user_id: user.id, activity_id: announce.id})
        |> Repo.preload(:activity)

      refute Streamer.filtered_by_user?(user, notification)
    end

    test "it streams boosts of mastodon user in the 'user' stream", %{
      user: user,
      token: oauth_token
    } do
      Streamer.get_topic_and_add_socket("user", user, oauth_token)

      other_user = insert(:user)
      {:ok, activity} = CommonAPI.post(other_user, %{status: "hey"})

      data =
        File.read!("test/fixtures/mastodon-announce.json")
        |> Jason.decode!()
        |> Map.put("object", activity.data["object"])
        |> Map.put("actor", user.ap_id)

      {:ok, %Pleroma.Activity{data: _data, local: false} = announce} =
        Pleroma.Web.ActivityPub.Transmogrifier.handle_incoming(data)

      assert_receive {:render_with_user, Pleroma.Web.StreamerView, "update.json", ^announce, _}
      refute Streamer.filtered_by_user?(user, announce)
    end

    test "it sends notify to in the 'user' stream", %{
      user: user,
      token: oauth_token,
      notify: notify
    } do
      Streamer.get_topic_and_add_socket("user", user, oauth_token)
      Streamer.stream("user", notify)

      assert_receive {:render_with_user, _, _, ^notify, _}
      refute Streamer.filtered_by_user?(user, notify)
    end

    test "it sends notify to in the 'user:notification' stream", %{
      user: user,
      token: oauth_token,
      notify: notify
    } do
      Streamer.get_topic_and_add_socket("user:notification", user, oauth_token)
      Streamer.stream("user:notification", notify)

      assert_receive {:render_with_user, _, _, ^notify, _}
      refute Streamer.filtered_by_user?(user, notify)
    end

    test "it sends chat messages to the 'user:pleroma_chat' stream", %{
      user: user,
      token: oauth_token
    } do
      other_user = insert(:user)

      {:ok, create_activity} =
        CommonAPI.post_chat_message(other_user, user, "hey cirno", idempotency_key: "123")

      object = Object.normalize(create_activity, fetch: false)
      chat = Chat.get(user.id, other_user.ap_id)
      cm_ref = MessageReference.for_chat_and_object(chat, object)
      cm_ref = %{cm_ref | chat: chat, object: object}

      Streamer.get_topic_and_add_socket("user:pleroma_chat", user, oauth_token)
      Streamer.stream("user:pleroma_chat", {user, cm_ref})

      text =
        StreamerView.render(
          "chat_update.json",
          %{chat_message_reference: cm_ref},
          "user:pleroma_chat:#{user.id}"
        )

      assert text =~ "hey cirno"
      assert_receive {:text, ^text}
    end

    test "it sends chat messages to the 'user' stream", %{user: user, token: oauth_token} do
      other_user = insert(:user)

      {:ok, create_activity} = CommonAPI.post_chat_message(other_user, user, "hey cirno")
      object = Object.normalize(create_activity, fetch: false)
      chat = Chat.get(user.id, other_user.ap_id)
      cm_ref = MessageReference.for_chat_and_object(chat, object)
      cm_ref = %{cm_ref | chat: chat, object: object}

      Streamer.get_topic_and_add_socket("user", user, oauth_token)
      Streamer.stream("user", {user, cm_ref})

      text =
        StreamerView.render(
          "chat_update.json",
          %{chat_message_reference: cm_ref},
          "user:#{user.id}"
        )

      assert text =~ "hey cirno"
      assert_receive {:text, ^text}
    end

    test "it sends chat message notifications to the 'user:notification' stream", %{
      user: user,
      token: oauth_token
    } do
      other_user = insert(:user)

      {:ok, create_activity} = CommonAPI.post_chat_message(other_user, user, "hey")

      notify =
        Repo.get_by(Pleroma.Notification, user_id: user.id, activity_id: create_activity.id)
        |> Repo.preload(:activity)

      Streamer.get_topic_and_add_socket("user:notification", user, oauth_token)
      Streamer.stream("user:notification", notify)

      assert_receive {:render_with_user, _, _, ^notify, _}
      refute Streamer.filtered_by_user?(user, notify)
    end

    test "it doesn't send notify to the 'user:notification' stream when a user is blocked", %{
      user: user,
      token: oauth_token
    } do
      blocked = insert(:user)
      {:ok, _user_relationship} = User.block(user, blocked)

      Streamer.get_topic_and_add_socket("user:notification", user, oauth_token)

      {:ok, activity} = CommonAPI.post(user, %{status: ":("})
      {:ok, _} = CommonAPI.favorite(activity.id, blocked)

      refute_receive _
    end

    test "it doesn't send notify to the 'user:notification' stream when a thread is muted", %{
      user: user,
      token: oauth_token
    } do
      user2 = insert(:user)

      {:ok, activity} = CommonAPI.post(user, %{status: "super hot take"})
      {:ok, _} = CommonAPI.add_mute(activity, user)

      Streamer.get_topic_and_add_socket("user:notification", user, oauth_token)

      {:ok, favorite_activity} = CommonAPI.favorite(activity.id, user2)

      refute_receive _
      assert Streamer.filtered_by_user?(user, favorite_activity)
    end

    test "it sends favorite to 'user:notification' stream'", %{
      user: user,
      token: oauth_token
    } do
      user2 = insert(:user, %{ap_id: "https://hecking-lewd-place.com/user/meanie"})

      {:ok, activity} = CommonAPI.post(user, %{status: "super hot take"})
      Streamer.get_topic_and_add_socket("user:notification", user, oauth_token)
      {:ok, favorite_activity} = CommonAPI.favorite(activity.id, user2)

      assert_receive {:render_with_user, _, "notification.json", notif, _}
      assert notif.activity.id == favorite_activity.id
      refute Streamer.filtered_by_user?(user, notif)
    end

    test "it doesn't send the 'user:notification' stream' when a domain is blocked", %{
      user: user,
      token: oauth_token
    } do
      user2 = insert(:user, %{ap_id: "https://hecking-lewd-place.com/user/meanie"})

      {:ok, user} = User.block_domain(user, "hecking-lewd-place.com")
      {:ok, activity} = CommonAPI.post(user, %{status: "super hot take"})
      Streamer.get_topic_and_add_socket("user:notification", user, oauth_token)
      {:ok, favorite_activity} = CommonAPI.favorite(activity.id, user2)

      refute_receive _
      assert Streamer.filtered_by_user?(user, favorite_activity)
    end

    test "it sends follow activities to the 'user:notification' stream", %{
      user: user,
      token: oauth_token
    } do
      user2 = insert(:user)

      Streamer.get_topic_and_add_socket("user:notification", user, oauth_token)
      {:ok, _follower, _followed, follow_activity} = CommonAPI.follow(user, user2)

      assert_receive {:render_with_user, _, "notification.json", notif, _}
      assert notif.activity.id == follow_activity.id
      refute Streamer.filtered_by_user?(user, notif)
    end

    test "it sends follow relationships updates to the 'user' stream", %{
      user: user,
      token: oauth_token
    } do
      user_id = user.id
      other_user = insert(:user)
      other_user_id = other_user.id

      Streamer.get_topic_and_add_socket("user", user, oauth_token)
      {:ok, _follower, _followed, _follow_activity} = CommonAPI.follow(other_user, user)

      assert_receive {:text, event}

      assert %{"event" => "pleroma:follow_relationships_update", "payload" => payload} =
               Jason.decode!(event)

      assert %{
               "follower" => %{
                 "follower_count" => 0,
                 "following_count" => 0,
                 "id" => ^user_id
               },
               "following" => %{
                 "follower_count" => 0,
                 "following_count" => 0,
                 "id" => ^other_user_id
               },
               "state" => "follow_pending"
             } = Jason.decode!(payload)

      assert_receive {:text, event}

      assert %{"event" => "pleroma:follow_relationships_update", "payload" => payload} =
               Jason.decode!(event)

      assert %{
               "follower" => %{
                 "follower_count" => 0,
                 "following_count" => 1,
                 "id" => ^user_id
               },
               "following" => %{
                 "follower_count" => 1,
                 "following_count" => 0,
                 "id" => ^other_user_id
               },
               "state" => "follow_accept"
             } = Jason.decode!(payload)
    end

    test "it streams edits in the 'user' stream", %{user: user, token: oauth_token} do
      sender = insert(:user)
      {:ok, _, _, _} = CommonAPI.follow(sender, user)

      {:ok, activity} = CommonAPI.post(sender, %{status: "hey"})

      Streamer.get_topic_and_add_socket("user", user, oauth_token)
      {:ok, edited} = CommonAPI.update(activity, sender, %{status: "mew mew"})
      create = Pleroma.Activity.get_create_by_object_ap_id_with_object(activity.object.data["id"])

      assert_receive {:render_with_user, _, "status_update.json", ^create, _}
      refute Streamer.filtered_by_user?(user, edited)
    end

    test "it streams own edits in the 'user' stream", %{user: user, token: oauth_token} do
      {:ok, activity} = CommonAPI.post(user, %{status: "hey"})

      Streamer.get_topic_and_add_socket("user", user, oauth_token)
      {:ok, edited} = CommonAPI.update(activity, user, %{status: "mew mew"})
      create = Pleroma.Activity.get_create_by_object_ap_id_with_object(activity.object.data["id"])

      assert_receive {:render_with_user, _, "status_update.json", ^create, _}
      refute Streamer.filtered_by_user?(user, edited)
    end

    test "it streams posts containing followed hashtags on the 'user' stream", %{
      user: user,
      token: oauth_token
    } do
      hashtag = insert(:hashtag, %{name: "tenshi"})
      other_user = insert(:user)
      {:ok, user} = User.follow_hashtag(user, hashtag)

      Streamer.get_topic_and_add_socket("user", user, oauth_token)
      {:ok, activity} = CommonAPI.post(other_user, %{status: "hey #tenshi"})

      assert_receive {:render_with_user, _, "update.json", ^activity, _}
    end

    test "should not stream private posts containing followed hashtags on the 'user' stream", %{
      user: user,
      token: oauth_token
    } do
      hashtag = insert(:hashtag, %{name: "tenshi"})
      other_user = insert(:user)
      {:ok, user} = User.follow_hashtag(user, hashtag)

      Streamer.get_topic_and_add_socket("user", user, oauth_token)

      {:ok, activity} =
        CommonAPI.post(other_user, %{status: "hey #tenshi", visibility: "private"})

      refute_receive {:render_with_user, _, "update.json", ^activity, _}
    end
  end

  describe "public streams" do
    test "it sends to public (authenticated)" do
      %{user: user, token: oauth_token} = oauth_access(["read"])
      other_user = insert(:user)

      Streamer.get_topic_and_add_socket("public", user, oauth_token)

      {:ok, activity} = CommonAPI.post(other_user, %{status: "Test"})
      assert_receive {:render_with_user, _, _, ^activity, _}
      refute Streamer.filtered_by_user?(other_user, activity)
    end

    test "it sends to public (unauthenticated)" do
      user = insert(:user)

      Streamer.get_topic_and_add_socket("public", nil, nil)

      {:ok, activity} = CommonAPI.post(user, %{status: "Test"})
      activity_id = activity.id
      assert_receive {:text, event}
      assert %{"event" => "update", "payload" => payload} = Jason.decode!(event)
      assert %{"id" => ^activity_id} = Jason.decode!(payload)

      {:ok, _} = CommonAPI.delete(activity.id, user)
      assert_receive {:text, event}
      assert %{"event" => "delete", "payload" => ^activity_id} = Jason.decode!(event)
    end

    test "handles deletions" do
      %{user: user, token: oauth_token} = oauth_access(["read"])
      other_user = insert(:user)
      {:ok, activity} = CommonAPI.post(other_user, %{status: "Test"})

      Streamer.get_topic_and_add_socket("public", user, oauth_token)

      {:ok, _} = CommonAPI.delete(activity.id, other_user)
      activity_id = activity.id
      assert_receive {:text, event}
      assert %{"event" => "delete", "payload" => ^activity_id} = Jason.decode!(event)
    end

    test "it streams edits in the 'public' stream" do
      sender = insert(:user)

      Streamer.get_topic_and_add_socket("public", nil, nil)
      {:ok, activity} = CommonAPI.post(sender, %{status: "hey"})
      assert_receive {:text, _}

      {:ok, edited} = CommonAPI.update(activity, sender, %{status: "mew mew"})

      edited = Pleroma.Activity.normalize(edited)

      %{id: activity_id} = Pleroma.Activity.get_create_by_object_ap_id(edited.object.data["id"])

      assert_receive {:text, event}
      assert %{"event" => "status.update", "payload" => payload} = Jason.decode!(event)
      assert %{"id" => ^activity_id} = Jason.decode!(payload)
      refute Streamer.filtered_by_user?(sender, edited)
    end

    test "it streams multiple edits in the 'public' stream correctly" do
      sender = insert(:user)

      Streamer.get_topic_and_add_socket("public", nil, nil)
      {:ok, activity} = CommonAPI.post(sender, %{status: "hey"})
      assert_receive {:text, _}

      {:ok, edited} = CommonAPI.update(activity, sender, %{status: "mew mew"})

      edited = Pleroma.Activity.normalize(edited)

      %{id: activity_id} = Pleroma.Activity.get_create_by_object_ap_id(edited.object.data["id"])

      assert_receive {:text, event}
      assert %{"event" => "status.update", "payload" => payload} = Jason.decode!(event)
      assert %{"id" => ^activity_id} = Jason.decode!(payload)
      refute Streamer.filtered_by_user?(sender, edited)

      {:ok, edited} = CommonAPI.update(activity, sender, %{status: "mew mew 2"})

      edited = Pleroma.Activity.normalize(edited)

      %{id: activity_id} = Pleroma.Activity.get_create_by_object_ap_id(edited.object.data["id"])
      assert_receive {:text, event}
      assert %{"event" => "status.update", "payload" => payload} = Jason.decode!(event)
      assert %{"id" => ^activity_id, "content" => "mew mew 2"} = Jason.decode!(payload)
      refute Streamer.filtered_by_user?(sender, edited)
    end
  end

  describe "thread_containment/2" do
    test "it filters to user if recipients invalid and thread containment is enabled" do
      clear_config([:instance, :skip_thread_containment], false)
      author = insert(:user)
      %{user: user, token: oauth_token} = oauth_access(["read"])
      User.follow(user, author, :follow_accept)

      activity =
        insert(:note_activity,
          note:
            insert(:note,
              user: author,
              data: %{"to" => ["TEST-FFF"]}
            )
        )

      Streamer.get_topic_and_add_socket("public", user, oauth_token)
      Streamer.stream("public", activity)
      assert_receive {:render_with_user, _, _, ^activity, _}
      assert Streamer.filtered_by_user?(user, activity)
    end

    test "it sends message if recipients invalid and thread containment is disabled" do
      clear_config([:instance, :skip_thread_containment], true)
      author = insert(:user)
      %{user: user, token: oauth_token} = oauth_access(["read"])
      User.follow(user, author, :follow_accept)

      activity =
        insert(:note_activity,
          note:
            insert(:note,
              user: author,
              data: %{"to" => ["TEST-FFF"]}
            )
        )

      Streamer.get_topic_and_add_socket("public", user, oauth_token)
      Streamer.stream("public", activity)

      assert_receive {:render_with_user, _, _, ^activity, _}
      refute Streamer.filtered_by_user?(user, activity)
    end

    test "it sends message if recipients invalid and thread containment is enabled but user's thread containment is disabled" do
      clear_config([:instance, :skip_thread_containment], false)
      author = insert(:user)
      user = insert(:user, skip_thread_containment: true)
      %{token: oauth_token} = oauth_access(["read"], user: user)
      User.follow(user, author, :follow_accept)

      activity =
        insert(:note_activity,
          note:
            insert(:note,
              user: author,
              data: %{"to" => ["TEST-FFF"]}
            )
        )

      Streamer.get_topic_and_add_socket("public", user, oauth_token)
      Streamer.stream("public", activity)

      assert_receive {:render_with_user, _, _, ^activity, _}
      refute Streamer.filtered_by_user?(user, activity)
    end
  end

  describe "blocks" do
    setup do: oauth_access(["read"])

    test "it filters messages involving blocked users", %{user: user, token: oauth_token} do
      blocked_user = insert(:user)
      {:ok, _user_relationship} = User.block(user, blocked_user)

      Streamer.get_topic_and_add_socket("public", user, oauth_token)
      {:ok, activity} = CommonAPI.post(blocked_user, %{status: "Test"})
      assert_receive {:render_with_user, _, _, ^activity, _}
      assert Streamer.filtered_by_user?(user, activity)
    end

    test "it filters messages transitively involving blocked users", %{
      user: blocker,
      token: blocker_token
    } do
      blockee = insert(:user)
      friend = insert(:user)

      Streamer.get_topic_and_add_socket("public", blocker, blocker_token)

      {:ok, _user_relationship} = User.block(blocker, blockee)

      {:ok, activity_one} = CommonAPI.post(friend, %{status: "hey! @#{blockee.nickname}"})

      assert_receive {:render_with_user, _, _, ^activity_one, _}
      assert Streamer.filtered_by_user?(blocker, activity_one)

      {:ok, activity_two} = CommonAPI.post(blockee, %{status: "hey! @#{friend.nickname}"})

      assert_receive {:render_with_user, _, _, ^activity_two, _}
      assert Streamer.filtered_by_user?(blocker, activity_two)

      {:ok, activity_three} = CommonAPI.post(blockee, %{status: "hey! @#{blocker.nickname}"})

      assert_receive {:render_with_user, _, _, ^activity_three, _}
      assert Streamer.filtered_by_user?(blocker, activity_three)
    end
  end

  describe "lists" do
    setup do: oauth_access(["read"])

    test "it doesn't send unwanted DMs to list", %{user: user_a, token: user_a_token} do
      user_b = insert(:user)
      user_c = insert(:user)

      {:ok, user_a, user_b} = User.follow(user_a, user_b)

      {:ok, list} = List.create("Test", user_a)
      {:ok, list} = List.follow(list, user_b)

      Streamer.get_topic_and_add_socket("list", user_a, user_a_token, %{"list" => list.id})

      {:ok, _activity} =
        CommonAPI.post(user_b, %{
          status: "@#{user_c.nickname} Test",
          visibility: "direct"
        })

      refute_receive _
    end

    test "it doesn't send unwanted private posts to list", %{user: user_a, token: user_a_token} do
      user_b = insert(:user)

      {:ok, list} = List.create("Test", user_a)
      {:ok, list} = List.follow(list, user_b)

      Streamer.get_topic_and_add_socket("list", user_a, user_a_token, %{"list" => list.id})

      {:ok, _activity} =
        CommonAPI.post(user_b, %{
          status: "Test",
          visibility: "private"
        })

      refute_receive _
    end

    test "it sends wanted private posts to list", %{user: user_a, token: user_a_token} do
      user_b = insert(:user)

      {:ok, user_a, user_b} = User.follow(user_a, user_b)

      {:ok, list} = List.create("Test", user_a)
      {:ok, list} = List.follow(list, user_b)

      Streamer.get_topic_and_add_socket("list", user_a, user_a_token, %{"list" => list.id})

      {:ok, activity} =
        CommonAPI.post(user_b, %{
          status: "Test",
          visibility: "private"
        })

      assert_receive {:render_with_user, _, _, ^activity, _}
      refute Streamer.filtered_by_user?(user_a, activity)
    end
  end

  describe "muted reblogs" do
    setup do: oauth_access(["read"])

    test "it filters muted reblogs", %{user: user1, token: user1_token} do
      user2 = insert(:user)
      user3 = insert(:user)
      CommonAPI.follow(user2, user1)
      CommonAPI.hide_reblogs(user2, user1)

      {:ok, create_activity} = CommonAPI.post(user3, %{status: "I'm kawen"})

      Streamer.get_topic_and_add_socket("user", user1, user1_token)
      {:ok, announce_activity} = CommonAPI.repeat(create_activity.id, user2)
      assert_receive {:render_with_user, _, _, ^announce_activity, _}
      assert Streamer.filtered_by_user?(user1, announce_activity)
    end

    test "it filters reblog notification for reblog-muted actors", %{
      user: user1,
      token: user1_token
    } do
      user2 = insert(:user)
      CommonAPI.follow(user2, user1)
      CommonAPI.hide_reblogs(user2, user1)

      {:ok, create_activity} = CommonAPI.post(user1, %{status: "I'm kawen"})
      Streamer.get_topic_and_add_socket("user", user1, user1_token)
      {:ok, _announce_activity} = CommonAPI.repeat(create_activity.id, user2)

      assert_receive {:render_with_user, _, "notification.json", notif, _}
      assert Streamer.filtered_by_user?(user1, notif)
    end

    test "it send non-reblog notification for reblog-muted actors", %{
      user: user1,
      token: user1_token
    } do
      user2 = insert(:user)
      CommonAPI.follow(user2, user1)
      CommonAPI.hide_reblogs(user2, user1)

      {:ok, create_activity} = CommonAPI.post(user1, %{status: "I'm kawen"})
      Streamer.get_topic_and_add_socket("user", user1, user1_token)
      {:ok, _favorite_activity} = CommonAPI.favorite(create_activity.id, user2)

      assert_receive {:render_with_user, _, "notification.json", notif, _}
      refute Streamer.filtered_by_user?(user1, notif)
    end
  end

  describe "muted threads" do
    test "it filters posts from muted threads" do
      user = insert(:user)
      %{user: user2, token: user2_token} = oauth_access(["read"])
      Streamer.get_topic_and_add_socket("user", user2, user2_token)

      {:ok, user2, user, _activity} = CommonAPI.follow(user, user2)
      {:ok, activity} = CommonAPI.post(user, %{status: "super hot take"})
      {:ok, _} = CommonAPI.add_mute(activity, user2)

      assert_receive {:render_with_user, _, _, ^activity, _}
      assert Streamer.filtered_by_user?(user2, activity)
    end
  end

  describe "direct streams" do
    setup do: oauth_access(["read"])

    test "it sends conversation update to the 'direct' stream", %{user: user, token: oauth_token} do
      another_user = insert(:user)

      Streamer.get_topic_and_add_socket("direct", user, oauth_token)

      {:ok, _create_activity} =
        CommonAPI.post(another_user, %{
          status: "hey @#{user.nickname}",
          visibility: "direct"
        })

      assert_receive {:text, received_event}

      assert %{"event" => "conversation", "payload" => received_payload} =
               Jason.decode!(received_event)

      assert %{"last_status" => last_status} = Jason.decode!(received_payload)
      [participation] = Participation.for_user(user)
      assert last_status["pleroma"]["direct_conversation_id"] == participation.id
    end

    test "it doesn't send conversation update to the 'direct' stream when the last message in the conversation is deleted",
         %{user: user, token: oauth_token} do
      another_user = insert(:user)

      Streamer.get_topic_and_add_socket("direct", user, oauth_token)

      {:ok, create_activity} =
        CommonAPI.post(another_user, %{
          status: "hi @#{user.nickname}",
          visibility: "direct"
        })

      create_activity_id = create_activity.id
      assert_receive {:render_with_user, _, _, ^create_activity, _}
      assert_receive {:text, received_conversation1}
      assert %{"event" => "conversation", "payload" => _} = Jason.decode!(received_conversation1)

      {:ok, _} = CommonAPI.delete(create_activity_id, another_user)

      assert_receive {:text, received_event}

      assert %{"event" => "delete", "payload" => ^create_activity_id} =
               Jason.decode!(received_event)

      refute_receive _
    end

    @tag :erratic
    test "it sends conversation update to the 'direct' stream when a message is deleted", %{
      user: user,
      token: oauth_token
    } do
      another_user = insert(:user)
      Streamer.get_topic_and_add_socket("direct", user, oauth_token)

      {:ok, create_activity} =
        CommonAPI.post(another_user, %{
          status: "hi @#{user.nickname}",
          visibility: "direct"
        })

      {:ok, create_activity2} =
        CommonAPI.post(another_user, %{
          status: "hi @#{user.nickname} 2",
          in_reply_to_status_id: create_activity.id,
          visibility: "direct"
        })

      assert_receive {:render_with_user, _, _, ^create_activity, _}
      assert_receive {:render_with_user, _, _, ^create_activity2, _}
      assert_receive {:text, received_conversation1}
      assert %{"event" => "conversation", "payload" => _} = Jason.decode!(received_conversation1)
      assert_receive {:text, received_conversation1}
      assert %{"event" => "conversation", "payload" => _} = Jason.decode!(received_conversation1)

      {:ok, _} = CommonAPI.delete(create_activity2.id, another_user)

      assert_receive {:text, received_event}
      assert %{"event" => "delete", "payload" => _} = Jason.decode!(received_event)

      assert_receive {:text, received_event}

      assert %{"event" => "conversation", "payload" => received_payload} =
               Jason.decode!(received_event)

      assert %{"last_status" => last_status} = Jason.decode!(received_payload)
      assert last_status["id"] == to_string(create_activity.id)
    end
  end

  describe "stop streaming if token got revoked" do
    setup do
      child_proc = fn start, finalize ->
        fn ->
          start.()

          receive do
            {StreamerTest, :ready} ->
              assert_receive {:render_with_user, _, "update.json", _, _}

              receive do
                {StreamerTest, :revoked} -> finalize.()
              end
          end
        end
      end

      starter = fn user, token ->
        fn -> Streamer.get_topic_and_add_socket("user", user, token) end
      end

      hit = fn -> assert_receive :close end
      miss = fn -> refute_receive :close end

      send_all = fn tasks, thing -> Enum.each(tasks, &send(&1.pid, thing)) end

      %{
        child_proc: child_proc,
        starter: starter,
        hit: hit,
        miss: miss,
        send_all: send_all
      }
    end

    test "do not revoke other tokens", %{
      child_proc: child_proc,
      starter: starter,
      hit: hit,
      miss: miss,
      send_all: send_all
    } do
      %{user: user, token: token} = oauth_access(["read"])
      %{token: token2} = oauth_access(["read"], user: user)
      %{user: user2, token: user2_token} = oauth_access(["read"])

      post_user = insert(:user)
      CommonAPI.follow(post_user, user)
      CommonAPI.follow(post_user, user2)

      tasks = [
        Task.async(child_proc.(starter.(user, token), hit)),
        Task.async(child_proc.(starter.(user, token2), miss)),
        Task.async(child_proc.(starter.(user2, user2_token), miss))
      ]

      {:ok, _} =
        CommonAPI.post(post_user, %{
          status: "hi"
        })

      send_all.(tasks, {StreamerTest, :ready})

      Pleroma.Web.OAuth.Token.Strategy.Revoke.revoke(token)

      send_all.(tasks, {StreamerTest, :revoked})

      Enum.each(tasks, &Task.await/1)
    end

    test "revoke all streams for this token", %{
      child_proc: child_proc,
      starter: starter,
      hit: hit,
      send_all: send_all
    } do
      %{user: user, token: token} = oauth_access(["read"])

      post_user = insert(:user)
      CommonAPI.follow(post_user, user)

      tasks = [
        Task.async(child_proc.(starter.(user, token), hit)),
        Task.async(child_proc.(starter.(user, token), hit))
      ]

      {:ok, _} =
        CommonAPI.post(post_user, %{
          status: "hi"
        })

      send_all.(tasks, {StreamerTest, :ready})

      Pleroma.Web.OAuth.Token.Strategy.Revoke.revoke(token)

      send_all.(tasks, {StreamerTest, :revoked})

      Enum.each(tasks, &Task.await/1)
    end
  end
end
