# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.SideEffectsTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.Chat
  alias Pleroma.Chat.MessageReference
  alias Pleroma.Notification
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Builder
  alias Pleroma.Web.ActivityPub.SideEffects
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.CommonAPI.ActivityDraft

  import Mock
  import Pleroma.Factory

  defp get_announces_of_object(%{data: %{"id" => id}} = _object) do
    Pleroma.Activity.Queries.by_type("Announce")
    |> Pleroma.Activity.Queries.by_object_id(id)
    |> Pleroma.Repo.all()
  end

  describe "handle_after_transaction" do
    test "it streams out notifications and streams" do
      author = insert(:user, local: true)
      recipient = insert(:user, local: true)

      {:ok, chat_message_data, _meta} = Builder.chat_message(author, recipient.ap_id, "hey")

      {:ok, create_activity_data, _meta} =
        Builder.create(author, chat_message_data["id"], [recipient.ap_id])

      {:ok, create_activity, _meta} = ActivityPub.persist(create_activity_data, local: false)

      {:ok, _create_activity, meta} =
        SideEffects.handle(create_activity, local: false, object_data: chat_message_data)

      assert [notification] = meta[:notifications]

      with_mocks([
        {
          Pleroma.Web.Streamer,
          [],
          [
            stream: fn _, _ -> nil end
          ]
        }
      ]) do
        SideEffects.handle_after_transaction(meta)

        assert called(Pleroma.Web.Streamer.stream(["user", "user:notification"], notification))
        assert called(Pleroma.Web.Streamer.stream(["user", "user:pleroma_chat"], :_))

        assert_enqueued(
          worker: "Pleroma.Workers.WebPusherWorker",
          args: %{"notification_id" => notification.id, "op" => "web_push"}
        )
      end
    end
  end

  describe "blocking users" do
    setup do
      user = insert(:user)
      blocked = insert(:user)
      User.follow(blocked, user)
      User.follow(user, blocked)

      {:ok, block_data, []} = Builder.block(user, blocked)
      {:ok, block, _meta} = ActivityPub.persist(block_data, local: true)

      %{user: user, blocked: blocked, block: block}
    end

    test "it unfollows and blocks", %{user: user, blocked: blocked, block: block} do
      assert User.following?(user, blocked)
      assert User.following?(blocked, user)

      {:ok, _, _} = SideEffects.handle(block)

      refute User.following?(user, blocked)
      refute User.following?(blocked, user)
      assert User.blocks?(user, blocked)
    end

    test "it updates following relationship", %{user: user, blocked: blocked, block: block} do
      {:ok, _, _} = SideEffects.handle(block)

      refute Pleroma.FollowingRelationship.get(user, blocked)
      assert User.get_follow_state(user, blocked) == nil
      assert User.get_follow_state(blocked, user) == nil
      assert User.get_follow_state(user, blocked, nil) == nil
      assert User.get_follow_state(blocked, user, nil) == nil
    end

    test "it blocks but does not unfollow if the relevant setting is set", %{
      user: user,
      blocked: blocked,
      block: block
    } do
      clear_config([:activitypub, :unfollow_blocked], false)
      assert User.following?(user, blocked)
      assert User.following?(blocked, user)

      {:ok, _, _} = SideEffects.handle(block)

      refute User.following?(user, blocked)
      assert User.following?(blocked, user)
      assert User.blocks?(user, blocked)
    end
  end

  describe "update users" do
    setup do
      user = insert(:user, local: false)

      {:ok, update_data, []} =
        Builder.update(user, %{"id" => user.ap_id, "type" => "Person", "name" => "new name!"})

      {:ok, update, _meta} = ActivityPub.persist(update_data, local: true)

      %{user: user, update_data: update_data, update: update}
    end

    test "it updates the user", %{user: user, update: update} do
      {:ok, _, _} = SideEffects.handle(update)
      user = User.get_by_id(user.id)
      assert user.name == "new name!"
    end

    test "it uses a given changeset to update", %{user: user, update: update} do
      changeset = Ecto.Changeset.change(user, %{default_scope: "direct"})

      assert user.default_scope == "public"
      {:ok, _, _} = SideEffects.handle(update, user_update_changeset: changeset)
      user = User.get_by_id(user.id)
      assert user.default_scope == "direct"
    end
  end

  describe "update notes" do
    setup do
      make_time = fn ->
        Pleroma.Web.ActivityPub.Utils.make_date()
      end

      user = insert(:user)
      note = insert(:note, user: user, data: %{"published" => make_time.()})
      _note_activity = insert(:note_activity, note: note)

      updated_note =
        note.data
        |> Map.put("summary", "edited summary")
        |> Map.put("content", "edited content")
        |> Map.put("updated", make_time.())

      {:ok, update_data, []} = Builder.update(user, updated_note)
      {:ok, update, _meta} = ActivityPub.persist(update_data, local: true)

      %{
        user: user,
        note: note,
        object_id: note.id,
        update_data: update_data,
        update: update,
        updated_note: updated_note
      }
    end

    test "it updates the note", %{
      object_id: object_id,
      update: update,
      updated_note: updated_note
    } do
      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)
      updated_time = updated_note["updated"]

      new_note = Pleroma.Object.get_by_id(object_id)

      assert %{
               "summary" => "edited summary",
               "content" => "edited content",
               "updated" => ^updated_time
             } = new_note.data
    end

    test "it rejects updates with no updated attribute in object", %{
      object_id: object_id,
      update: update,
      updated_note: updated_note
    } do
      old_note = Pleroma.Object.get_by_id(object_id)
      updated_note = Map.drop(updated_note, ["updated"])
      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)
      new_note = Pleroma.Object.get_by_id(object_id)
      assert old_note.data == new_note.data
    end

    test "it rejects updates with updated attribute older than what we have in the original object",
         %{
           object_id: object_id,
           update: update,
           updated_note: updated_note
         } do
      old_note = Pleroma.Object.get_by_id(object_id)
      {:ok, creation_time, _} = DateTime.from_iso8601(old_note.data["published"])

      updated_note =
        Map.put(updated_note, "updated", DateTime.to_iso8601(DateTime.add(creation_time, -10)))

      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)
      new_note = Pleroma.Object.get_by_id(object_id)
      assert old_note.data == new_note.data
    end

    test "it rejects updates with updated attribute older than the last Update", %{
      object_id: object_id,
      update: update,
      updated_note: updated_note
    } do
      old_note = Pleroma.Object.get_by_id(object_id)
      {:ok, creation_time, _} = DateTime.from_iso8601(old_note.data["published"])

      updated_note =
        Map.put(updated_note, "updated", DateTime.to_iso8601(DateTime.add(creation_time, +10)))

      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)

      old_note = Pleroma.Object.get_by_id(object_id)
      {:ok, update_time, _} = DateTime.from_iso8601(old_note.data["updated"])

      updated_note =
        Map.put(updated_note, "updated", DateTime.to_iso8601(DateTime.add(update_time, -5)))

      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)

      new_note = Pleroma.Object.get_by_id(object_id)
      assert old_note.data == new_note.data
    end

    test "it updates using object_data", %{
      object_id: object_id,
      update: update,
      updated_note: updated_note
    } do
      updated_note = Map.put(updated_note, "summary", "mew mew")
      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)
      new_note = Pleroma.Object.get_by_id(object_id)
      assert %{"summary" => "mew mew", "content" => "edited content"} = new_note.data
    end

    test "it records the original note in formerRepresentations", %{
      note: note,
      object_id: object_id,
      update: update,
      updated_note: updated_note
    } do
      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)
      %{data: new_note} = Pleroma.Object.get_by_id(object_id)
      assert %{"summary" => "edited summary", "content" => "edited content"} = new_note

      assert [Map.drop(note.data, ["id", "formerRepresentations"])] ==
               new_note["formerRepresentations"]["orderedItems"]

      assert new_note["formerRepresentations"]["totalItems"] == 1
    end

    test "it puts the original note at the front of formerRepresentations", %{
      user: user,
      note: note,
      object_id: object_id,
      update: update,
      updated_note: updated_note
    } do
      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)
      %{data: first_edit} = Pleroma.Object.get_by_id(object_id)

      second_updated_note =
        note.data
        |> Map.put("summary", "edited summary 2")
        |> Map.put("content", "edited content 2")
        |> Map.put(
          "updated",
          first_edit["updated"]
          |> DateTime.from_iso8601()
          |> elem(1)
          |> DateTime.add(10)
          |> DateTime.to_iso8601()
        )

      {:ok, second_update_data, []} = Builder.update(user, second_updated_note)
      {:ok, update, _meta} = ActivityPub.persist(second_update_data, local: true)
      {:ok, _, _} = SideEffects.handle(update, object_data: second_updated_note)
      %{data: new_note} = Pleroma.Object.get_by_id(object_id)
      assert %{"summary" => "edited summary 2", "content" => "edited content 2"} = new_note

      original_version = Map.drop(note.data, ["id", "formerRepresentations"])
      first_edit = Map.drop(first_edit, ["id", "formerRepresentations"])

      assert [first_edit, original_version] ==
               new_note["formerRepresentations"]["orderedItems"]

      assert new_note["formerRepresentations"]["totalItems"] == 2
    end

    test "it does not prepend to formerRepresentations if no actual changes are made", %{
      note: note,
      object_id: object_id,
      update: update,
      updated_note: updated_note
    } do
      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)
      %{data: first_edit} = Pleroma.Object.get_by_id(object_id)

      updated_note =
        updated_note
        |> Map.put(
          "updated",
          first_edit["updated"]
          |> DateTime.from_iso8601()
          |> elem(1)
          |> DateTime.add(10)
          |> DateTime.to_iso8601()
        )

      {:ok, _, _} = SideEffects.handle(update, object_data: updated_note)
      %{data: new_note} = Pleroma.Object.get_by_id(object_id)
      assert %{"summary" => "edited summary", "content" => "edited content"} = new_note

      original_version = Map.drop(note.data, ["id", "formerRepresentations"])

      assert [original_version] ==
               new_note["formerRepresentations"]["orderedItems"]

      assert new_note["formerRepresentations"]["totalItems"] == 1
    end
  end

  describe "update questions" do
    setup do
      user = insert(:user)

      question =
        insert(:question,
          user: user,
          data: %{"published" => Pleroma.Web.ActivityPub.Utils.make_date()}
        )

      %{user: user, data: question.data, id: question.id}
    end

    test "allows updating choice count without generating edit history", %{
      user: user,
      data: data,
      id: id
    } do
      new_choices =
        data["oneOf"]
        |> Enum.map(fn choice -> put_in(choice, ["replies", "totalItems"], 5) end)

      updated_question =
        data
        |> Map.put("oneOf", new_choices)
        |> Map.put("updated", Pleroma.Web.ActivityPub.Utils.make_date())

      {:ok, update_data, []} = Builder.update(user, updated_question)
      {:ok, update, _meta} = ActivityPub.persist(update_data, local: true)

      {:ok, _, _} = SideEffects.handle(update, object_data: updated_question)

      %{data: new_question} = Pleroma.Object.get_by_id(id)

      assert [%{"replies" => %{"totalItems" => 5}}, %{"replies" => %{"totalItems" => 5}}] =
               new_question["oneOf"]

      refute Map.has_key?(new_question, "formerRepresentations")
    end

    test "allows updating choice count without updated field", %{
      user: user,
      data: data,
      id: id
    } do
      new_choices =
        data["oneOf"]
        |> Enum.map(fn choice -> put_in(choice, ["replies", "totalItems"], 5) end)

      updated_question =
        data
        |> Map.put("oneOf", new_choices)

      {:ok, update_data, []} = Builder.update(user, updated_question)
      {:ok, update, _meta} = ActivityPub.persist(update_data, local: true)

      {:ok, _, _} = SideEffects.handle(update, object_data: updated_question)

      %{data: new_question} = Pleroma.Object.get_by_id(id)

      assert [%{"replies" => %{"totalItems" => 5}}, %{"replies" => %{"totalItems" => 5}}] =
               new_question["oneOf"]

      refute Map.has_key?(new_question, "formerRepresentations")
    end

    test "allows updating choice count with updated field same as the creation date", %{
      user: user,
      data: data,
      id: id
    } do
      new_choices =
        data["oneOf"]
        |> Enum.map(fn choice -> put_in(choice, ["replies", "totalItems"], 5) end)

      updated_question =
        data
        |> Map.put("oneOf", new_choices)
        |> Map.put("updated", data["published"])

      {:ok, update_data, []} = Builder.update(user, updated_question)
      {:ok, update, _meta} = ActivityPub.persist(update_data, local: true)

      {:ok, _, _} = SideEffects.handle(update, object_data: updated_question)

      %{data: new_question} = Pleroma.Object.get_by_id(id)

      assert [%{"replies" => %{"totalItems" => 5}}, %{"replies" => %{"totalItems" => 5}}] =
               new_question["oneOf"]

      refute Map.has_key?(new_question, "formerRepresentations")
    end
  end

  describe "EmojiReact objects" do
    setup do
      poster = insert(:user)
      user = insert(:user)

      {:ok, post} = CommonAPI.post(poster, %{status: "hey"})

      {:ok, emoji_react_data, []} = Builder.emoji_react(user, post.object, "👌")
      {:ok, emoji_react, _meta} = ActivityPub.persist(emoji_react_data, local: true)

      %{emoji_react: emoji_react, user: user, poster: poster}
    end

    test "adds the reaction to the object", %{emoji_react: emoji_react, user: user} do
      {:ok, emoji_react, _} = SideEffects.handle(emoji_react)
      object = Object.get_by_ap_id(emoji_react.data["object"])

      assert object.data["reaction_count"] == 1
      assert ["👌", [user.ap_id], nil] in object.data["reactions"]
    end

    test "creates a notification", %{emoji_react: emoji_react, poster: poster} do
      {:ok, emoji_react, _} = SideEffects.handle(emoji_react)
      assert Repo.get_by(Notification, user_id: poster.id, activity_id: emoji_react.id)
    end
  end

  describe "Question objects" do
    setup do
      user = insert(:user)
      question = build(:question, user: user)
      question_activity = build(:question_activity, question: question)
      activity_data = Map.put(question_activity.data, "object", question.data["id"])
      meta = [object_data: question.data, local: false]

      {:ok, activity, meta} = ActivityPub.persist(activity_data, meta)

      %{activity: activity, meta: meta}
    end

    test "enqueues the poll end", %{activity: activity, meta: meta} do
      {:ok, activity, meta} = SideEffects.handle(activity, meta)

      assert_enqueued(
        worker: Pleroma.Workers.PollWorker,
        args: %{op: "poll_end", activity_id: activity.id},
        scheduled_at: NaiveDateTime.from_iso8601!(meta[:object_data]["closed"])
      )
    end
  end

  describe "delete users with confirmation pending" do
    setup do
      user = insert(:user, is_confirmed: false)
      {:ok, delete_user_data, _meta} = Builder.delete(user, user.ap_id)
      {:ok, delete_user, _meta} = ActivityPub.persist(delete_user_data, local: true)
      {:ok, delete: delete_user, user: user}
    end

    test "when activation is required", %{delete: delete, user: user} do
      clear_config([:instance, :account_activation_required], true)
      {:ok, _, _} = SideEffects.handle(delete)
      ObanHelpers.perform_all()

      refute User.get_cached_by_id(user.id)
    end
  end

  describe "Undo objects" do
    setup do
      poster = insert(:user)
      user = insert(:user)
      {:ok, post} = CommonAPI.post(poster, %{status: "hey"})
      {:ok, like} = CommonAPI.favorite(post.id, user)
      {:ok, reaction} = CommonAPI.react_with_emoji(post.id, user, "👍")
      {:ok, announce} = CommonAPI.repeat(post.id, user)
      {:ok, block} = CommonAPI.block(poster, user)

      {:ok, undo_data, _meta} = Builder.undo(user, like)
      {:ok, like_undo, _meta} = ActivityPub.persist(undo_data, local: true)

      {:ok, undo_data, _meta} = Builder.undo(user, reaction)
      {:ok, reaction_undo, _meta} = ActivityPub.persist(undo_data, local: true)

      {:ok, undo_data, _meta} = Builder.undo(user, announce)
      {:ok, announce_undo, _meta} = ActivityPub.persist(undo_data, local: true)

      {:ok, undo_data, _meta} = Builder.undo(user, block)
      {:ok, block_undo, _meta} = ActivityPub.persist(undo_data, local: true)

      %{
        like_undo: like_undo,
        post: post,
        like: like,
        reaction_undo: reaction_undo,
        reaction: reaction,
        announce_undo: announce_undo,
        announce: announce,
        block_undo: block_undo,
        block: block,
        poster: poster,
        user: user
      }
    end

    test "deletes the original block", %{
      block_undo: block_undo,
      block: block
    } do
      {:ok, _block_undo, _meta} = SideEffects.handle(block_undo)

      refute Activity.get_by_id(block.id)
    end

    test "unblocks the blocked user", %{block_undo: block_undo, block: block} do
      blocker = User.get_by_ap_id(block.data["actor"])
      blocked = User.get_by_ap_id(block.data["object"])

      {:ok, _block_undo, _} = SideEffects.handle(block_undo)
      refute User.blocks?(blocker, blocked)
    end

    test "an announce undo removes the announce from the object", %{
      announce_undo: announce_undo,
      post: post
    } do
      {:ok, _announce_undo, _} = SideEffects.handle(announce_undo)

      object = Object.get_by_ap_id(post.data["object"])

      assert object.data["announcement_count"] == 0
      assert object.data["announcements"] == []
    end

    test "deletes the original announce", %{announce_undo: announce_undo, announce: announce} do
      {:ok, _announce_undo, _} = SideEffects.handle(announce_undo)
      refute Activity.get_by_id(announce.id)
    end

    test "a reaction undo removes the reaction from the object", %{
      reaction_undo: reaction_undo,
      post: post
    } do
      {:ok, _reaction_undo, _} = SideEffects.handle(reaction_undo)

      object = Object.get_by_ap_id(post.data["object"])

      assert object.data["reaction_count"] == 0
      assert object.data["reactions"] == []
    end

    test "deletes the original reaction", %{reaction_undo: reaction_undo, reaction: reaction} do
      {:ok, _reaction_undo, _} = SideEffects.handle(reaction_undo)
      refute Activity.get_by_id(reaction.id)
    end

    test "a like undo removes the like from the object", %{like_undo: like_undo, post: post} do
      {:ok, _like_undo, _} = SideEffects.handle(like_undo)

      object = Object.get_by_ap_id(post.data["object"])

      assert object.data["like_count"] == 0
      assert object.data["likes"] == []
    end

    test "deletes the original like", %{like_undo: like_undo, like: like} do
      {:ok, _like_undo, _} = SideEffects.handle(like_undo)
      refute Activity.get_by_id(like.id)
    end
  end

  describe "like objects" do
    setup do
      poster = insert(:user)
      user = insert(:user)
      {:ok, post} = CommonAPI.post(poster, %{status: "hey"})

      {:ok, like_data, _meta} = Builder.like(user, post.object)
      {:ok, like, _meta} = ActivityPub.persist(like_data, local: true)

      %{like: like, user: user, poster: poster}
    end

    test "add the like to the original object", %{like: like, user: user} do
      {:ok, like, _} = SideEffects.handle(like)
      object = Object.get_by_ap_id(like.data["object"])
      assert object.data["like_count"] == 1
      assert user.ap_id in object.data["likes"]
    end

    test "creates a notification", %{like: like, poster: poster} do
      {:ok, like, _} = SideEffects.handle(like)
      assert Repo.get_by(Notification, user_id: poster.id, activity_id: like.id)
    end
  end

  describe "creation of ChatMessages" do
    test "notifies the recipient" do
      author = insert(:user, local: false)
      recipient = insert(:user, local: true)

      {:ok, chat_message_data, _meta} = Builder.chat_message(author, recipient.ap_id, "hey")

      {:ok, create_activity_data, _meta} =
        Builder.create(author, chat_message_data["id"], [recipient.ap_id])

      {:ok, create_activity, _meta} = ActivityPub.persist(create_activity_data, local: false)

      {:ok, _create_activity, _meta} =
        SideEffects.handle(create_activity, local: false, object_data: chat_message_data)

      assert Repo.get_by(Notification, user_id: recipient.id, activity_id: create_activity.id)
    end

    test "it streams the created ChatMessage" do
      author = insert(:user, local: true)
      recipient = insert(:user, local: true)

      {:ok, chat_message_data, _meta} = Builder.chat_message(author, recipient.ap_id, "hey")

      {:ok, create_activity_data, _meta} =
        Builder.create(author, chat_message_data["id"], [recipient.ap_id])

      {:ok, create_activity, _meta} = ActivityPub.persist(create_activity_data, local: false)

      {:ok, _create_activity, meta} =
        SideEffects.handle(create_activity, local: false, object_data: chat_message_data)

      assert [_, _] = meta[:streamables]
    end

    test "it creates a Chat and MessageReferences for the local users and bumps the unread count, except for the author" do
      author = insert(:user, local: true)
      recipient = insert(:user, local: true)

      {:ok, chat_message_data, _meta} = Builder.chat_message(author, recipient.ap_id, "hey")

      {:ok, create_activity_data, _meta} =
        Builder.create(author, chat_message_data["id"], [recipient.ap_id])

      {:ok, create_activity, _meta} = ActivityPub.persist(create_activity_data, local: false)

      with_mocks([
        {
          Pleroma.Web.Streamer,
          [],
          [
            stream: fn _, _ -> nil end
          ]
        },
        {
          Pleroma.Web.Push,
          [],
          [
            send: fn _ -> nil end
          ]
        }
      ]) do
        {:ok, _create_activity, meta} =
          SideEffects.handle(create_activity, local: false, object_data: chat_message_data)

        # The notification gets created
        assert [notification] = meta[:notifications]
        assert notification.activity_id == create_activity.id

        # But it is not sent out
        refute called(Pleroma.Web.Streamer.stream(["user", "user:notification"], notification))
        refute called(Pleroma.Web.Push.send(notification))

        # Same for the user chat stream
        assert [{topics, _}, _] = meta[:streamables]
        assert topics == ["user", "user:pleroma_chat"]
        refute called(Pleroma.Web.Streamer.stream(["user", "user:pleroma_chat"], :_))

        chat = Chat.get(author.id, recipient.ap_id)

        [cm_ref] = MessageReference.for_chat_query(chat) |> Repo.all()

        assert cm_ref.object.data["content"] == "hey"
        assert cm_ref.unread == false

        chat = Chat.get(recipient.id, author.ap_id)

        [cm_ref] = MessageReference.for_chat_query(chat) |> Repo.all()

        assert cm_ref.object.data["content"] == "hey"
        assert cm_ref.unread == true
      end
    end

    test "it creates a Chat for the local users and bumps the unread count" do
      author = insert(:user, local: false)
      recipient = insert(:user, local: true)

      {:ok, chat_message_data, _meta} = Builder.chat_message(author, recipient.ap_id, "hey")

      {:ok, create_activity_data, _meta} =
        Builder.create(author, chat_message_data["id"], [recipient.ap_id])

      {:ok, create_activity, _meta} = ActivityPub.persist(create_activity_data, local: false)

      {:ok, _create_activity, _meta} =
        SideEffects.handle(create_activity, local: false, object_data: chat_message_data)

      # An object is created
      assert Object.get_by_ap_id(chat_message_data["id"])

      # The remote user won't get a chat
      chat = Chat.get(author.id, recipient.ap_id)
      refute chat

      # The local user will get a chat
      chat = Chat.get(recipient.id, author.ap_id)
      assert chat

      author = insert(:user, local: true)
      recipient = insert(:user, local: true)

      {:ok, chat_message_data, _meta} = Builder.chat_message(author, recipient.ap_id, "hey")

      {:ok, create_activity_data, _meta} =
        Builder.create(author, chat_message_data["id"], [recipient.ap_id])

      {:ok, create_activity, _meta} = ActivityPub.persist(create_activity_data, local: false)

      {:ok, _create_activity, _meta} =
        SideEffects.handle(create_activity, local: false, object_data: chat_message_data)

      # Both users are local and get the chat
      chat = Chat.get(author.id, recipient.ap_id)
      assert chat

      chat = Chat.get(recipient.id, author.ap_id)
      assert chat
    end
  end

  describe "announce objects" do
    setup do
      poster = insert(:user)
      user = insert(:user)
      {:ok, post} = CommonAPI.post(poster, %{status: "hey"})
      {:ok, private_post} = CommonAPI.post(poster, %{status: "hey", visibility: "private"})

      {:ok, announce_data, _meta} = Builder.announce(user, post.object, public: true)

      {:ok, private_announce_data, _meta} =
        Builder.announce(user, private_post.object, public: false)

      {:ok, relay_announce_data, _meta} =
        Builder.announce(Pleroma.Web.ActivityPub.Relay.get_actor(), post.object, public: true)

      {:ok, announce, _meta} = ActivityPub.persist(announce_data, local: true)
      {:ok, private_announce, _meta} = ActivityPub.persist(private_announce_data, local: true)
      {:ok, relay_announce, _meta} = ActivityPub.persist(relay_announce_data, local: true)

      %{
        announce: announce,
        user: user,
        poster: poster,
        private_announce: private_announce,
        relay_announce: relay_announce
      }
    end

    test "adds the announce to the original object", %{announce: announce, user: user} do
      {:ok, announce, _} = SideEffects.handle(announce)
      object = Object.get_by_ap_id(announce.data["object"])
      assert object.data["announcement_count"] == 1
      assert user.ap_id in object.data["announcements"]
    end

    test "does not add the announce to the original object if the actor is a service actor", %{
      relay_announce: announce
    } do
      {:ok, announce, _} = SideEffects.handle(announce)
      object = Object.get_by_ap_id(announce.data["object"])
      assert object.data["announcement_count"] == nil
    end

    test "creates a notification", %{announce: announce, poster: poster} do
      {:ok, announce, _} = SideEffects.handle(announce)
      assert Repo.get_by(Notification, user_id: poster.id, activity_id: announce.id)
    end
  end

  describe "removing a follower" do
    setup do
      user = insert(:user)
      followed = insert(:user)

      {:ok, _, _, follow_activity} = CommonAPI.follow(followed, user)

      {:ok, reject_data, []} = Builder.reject(followed, follow_activity)
      {:ok, reject, _meta} = ActivityPub.persist(reject_data, local: true)

      %{user: user, followed: followed, reject: reject}
    end

    test "", %{user: user, followed: followed, reject: reject} do
      assert User.following?(user, followed)
      assert Pleroma.FollowingRelationship.get(user, followed)

      {:ok, _, _} = SideEffects.handle(reject)

      refute User.following?(user, followed)
      refute Pleroma.FollowingRelationship.get(user, followed)
      assert User.get_follow_state(user, followed) == nil
      assert User.get_follow_state(user, followed, nil) == nil
    end
  end

  describe "removing a follower from remote" do
    setup do
      user = insert(:user)
      followed = insert(:user, local: false)

      # Mock a local-to-remote follow
      {:ok, follow_data, []} = Builder.follow(user, followed)

      follow_data =
        follow_data
        |> Map.put("state", "accept")

      {:ok, follow, _meta} = ActivityPub.persist(follow_data, local: true)
      {:ok, _, _} = SideEffects.handle(follow)

      # Mock a remote-to-local accept
      {:ok, accept_data, _} = Builder.accept(followed, follow)
      {:ok, accept, _} = ActivityPub.persist(accept_data, local: false)
      {:ok, _, _} = SideEffects.handle(accept)

      # Mock a remote-to-local reject
      {:ok, reject_data, []} = Builder.reject(followed, follow)
      {:ok, reject, _meta} = ActivityPub.persist(reject_data, local: false)

      %{user: user, followed: followed, reject: reject}
    end

    test "", %{user: user, followed: followed, reject: reject} do
      assert User.following?(user, followed)
      assert Pleroma.FollowingRelationship.get(user, followed)

      {:ok, _, _} = SideEffects.handle(reject)

      refute User.following?(user, followed)
      refute Pleroma.FollowingRelationship.get(user, followed)

      assert Pleroma.Web.ActivityPub.Utils.fetch_latest_follow(user, followed).data["state"] ==
               "reject"

      assert User.get_follow_state(user, followed) == nil
      assert User.get_follow_state(user, followed, nil) == nil
    end
  end

  describe "Group actors" do
    setup do
      poster =
        insert(:user,
          local: false,
          nickname: "poster@example.com",
          ap_id: "https://example.com/users/poster"
        )

      group = insert(:user, actor_type: "Group")

      make_create = fn mentioned_users ->
        mentions = mentioned_users |> Enum.map(fn u -> "@#{u.nickname}" end) |> Enum.join(" ")
        {:ok, draft} = ActivityDraft.create(poster, %{status: "#{mentions} hey"})

        create_activity_data =
          Utils.make_create_data(draft.changes |> Map.put(:published, nil), %{})
          |> put_in(["object", "id"], "https://example.com/object")
          |> put_in(["id"], "https://example.com/activity")

        assert Enum.all?(mentioned_users, fn u -> u.ap_id in create_activity_data["to"] end)

        create_activity_data
      end

      %{poster: poster, group: group, make_create: make_create}
    end

    test "group should boost it", %{make_create: make_create, group: group} do
      create_activity_data = make_create.([group])
      {:ok, create_activity, _meta} = ActivityPub.persist(create_activity_data, local: false)

      {:ok, _create_activity, _meta} =
        SideEffects.handle(create_activity,
          local: false,
          object_data: create_activity_data["object"]
        )

      object = Object.normalize(create_activity, fetch: false)
      assert [announce] = get_announces_of_object(object)
      assert announce.actor == group.ap_id
    end

    test "remote group should not boost it", %{make_create: make_create, group: group} do
      remote_group =
        insert(:user, actor_type: "Group", local: false, nickname: "remotegroup@example.com")

      create_activity_data = make_create.([group, remote_group])
      {:ok, create_activity, _meta} = ActivityPub.persist(create_activity_data, local: false)

      {:ok, _create_activity, _meta} =
        SideEffects.handle(create_activity,
          local: false,
          object_data: create_activity_data["object"]
        )

      object = Object.normalize(create_activity, fetch: false)
      assert [announce] = get_announces_of_object(object)
      assert announce.actor == group.ap_id
    end

    test "group should not boost it if group is blocking poster", %{
      make_create: make_create,
      group: group,
      poster: poster
    } do
      {:ok, _} = CommonAPI.block(poster, group)
      create_activity_data = make_create.([group])
      {:ok, create_activity, _meta} = ActivityPub.persist(create_activity_data, local: false)

      {:ok, _create_activity, _meta} =
        SideEffects.handle(create_activity,
          local: false,
          object_data: create_activity_data["object"]
        )

      object = Object.normalize(create_activity, fetch: false)
      assert [] = get_announces_of_object(object)
    end
  end
end
