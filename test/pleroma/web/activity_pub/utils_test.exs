# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.UtilsTest do
  use Pleroma.DataCase, async: true
  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.AdminAPI.AccountView
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  require Pleroma.Constants

  describe "strip_report_status_data/1" do
    test "does not break on issues with the reported activities" do
      reporter = insert(:user)
      target_account = insert(:user)
      {:ok, activity} = CommonAPI.post(target_account, %{status: "foobar"})
      context = Utils.generate_context_id()
      content = "foobar"
      post_id = activity.data["id"]

      res =
        Utils.make_flag_data(
          %{
            actor: reporter,
            context: context,
            account: target_account,
            statuses: [%{"id" => post_id}],
            content: content
          },
          %{}
        )

      res =
        res
        |> Map.put("object", res["object"] ++ [nil, 1, 5, "123"])

      {:ok, activity} = Pleroma.Web.ActivityPub.ActivityPub.insert(res)

      [user_id, object | _] = activity.data["object"]

      {:ok, stripped} = Utils.strip_report_status_data(activity)

      assert stripped.data["object"] == [user_id, object["id"]]
    end
  end

  describe "fetch the latest Follow" do
    test "fetches the latest Follow activity" do
      %Activity{data: %{"type" => "Follow"}} = activity = insert(:follow_activity)
      follower = User.get_cached_by_ap_id(activity.data["actor"])
      followed = User.get_cached_by_ap_id(activity.data["object"])

      assert activity == Utils.fetch_latest_follow(follower, followed)
    end
  end

  describe "determine_explicit_mentions()" do
    test "works with an object that has mentions" do
      object = %{
        "tag" => [
          %{
            "type" => "Mention",
            "href" => "https://example.com/~alyssa",
            "name" => "Alyssa P. Hacker"
          }
        ]
      }

      assert Utils.determine_explicit_mentions(object) == ["https://example.com/~alyssa"]
    end

    test "works with an object that does not have mentions" do
      object = %{
        "tag" => [
          %{"type" => "Hashtag", "href" => "https://example.com/tag/2hu", "name" => "2hu"}
        ]
      }

      assert Utils.determine_explicit_mentions(object) == []
    end

    test "works with an object that has mentions and other tags" do
      object = %{
        "tag" => [
          %{
            "type" => "Mention",
            "href" => "https://example.com/~alyssa",
            "name" => "Alyssa P. Hacker"
          },
          %{"type" => "Hashtag", "href" => "https://example.com/tag/2hu", "name" => "2hu"}
        ]
      }

      assert Utils.determine_explicit_mentions(object) == ["https://example.com/~alyssa"]
    end

    test "works with an object that has no tags" do
      object = %{}

      assert Utils.determine_explicit_mentions(object) == []
    end

    test "works with an object that has only IR tags" do
      object = %{"tag" => ["2hu"]}

      assert Utils.determine_explicit_mentions(object) == []
    end

    test "works with an object has tags as map" do
      object = %{
        "tag" => %{
          "type" => "Mention",
          "href" => "https://example.com/~alyssa",
          "name" => "Alyssa P. Hacker"
        }
      }

      assert Utils.determine_explicit_mentions(object) == ["https://example.com/~alyssa"]
    end
  end

  describe "make_like_data" do
    setup do
      user = insert(:user)
      other_user = insert(:user)
      third_user = insert(:user)
      [user: user, other_user: other_user, third_user: third_user]
    end

    test "addresses actor's follower address if the activity is public", %{
      user: user,
      other_user: other_user,
      third_user: third_user
    } do
      expected_to = Enum.sort([user.ap_id, other_user.follower_address])
      expected_cc = Enum.sort(["https://www.w3.org/ns/activitystreams#Public", third_user.ap_id])

      {:ok, activity} =
        CommonAPI.post(user, %{
          status:
            "hey @#{other_user.nickname}, @#{third_user.nickname} how about beering together this weekend?"
        })

      %{"to" => to, "cc" => cc} = Utils.make_like_data(other_user, activity, nil)
      assert Enum.sort(to) == expected_to
      assert Enum.sort(cc) == expected_cc
    end

    test "does not address actor's follower address if the activity is not public", %{
      user: user,
      other_user: other_user,
      third_user: third_user
    } do
      expected_to = Enum.sort([user.ap_id])
      expected_cc = [third_user.ap_id]

      {:ok, activity} =
        CommonAPI.post(user, %{
          status: "@#{other_user.nickname} @#{third_user.nickname} bought a new swimsuit!",
          visibility: "private"
        })

      %{"to" => to, "cc" => cc} = Utils.make_like_data(other_user, activity, nil)
      assert Enum.sort(to) == expected_to
      assert Enum.sort(cc) == expected_cc
    end
  end

  describe "make_json_ld_header/1" do
    test "makes jsonld header" do
      assert Utils.make_json_ld_header() == %{
               "@context" => [
                 "https://www.w3.org/ns/activitystreams",
                 "http://localhost:4001/schemas/litepub-0.1.jsonld",
                 %{
                   "@language" => "und"
                 }
               ]
             }
    end

    test "includes language if specified" do
      assert Utils.make_json_ld_header(%{"language" => "pl"}) == %{
               "@context" => [
                 "https://www.w3.org/ns/activitystreams",
                 "http://localhost:4001/schemas/litepub-0.1.jsonld",
                 %{
                   "@language" => "pl"
                 }
               ]
             }
    end
  end

  describe "get_existing_votes" do
    test "fetches existing votes" do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} =
        CommonAPI.post(user, %{
          status: "How do I pronounce LaTeX?",
          poll: %{
            options: ["laytekh", "lahtekh", "latex"],
            expires_in: 20,
            multiple: true
          }
        })

      object = Object.normalize(activity, fetch: false)
      {:ok, votes, object} = CommonAPI.vote(object, other_user, [0, 1])
      assert Enum.sort(Utils.get_existing_votes(other_user.ap_id, object)) == Enum.sort(votes)
    end

    test "fetches only Create activities" do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} =
        CommonAPI.post(user, %{
          status: "Are we living in a society?",
          poll: %{
            options: ["yes", "no"],
            expires_in: 20
          }
        })

      object = Object.normalize(activity, fetch: false)
      {:ok, [vote], object} = CommonAPI.vote(object, other_user, [0])
      {:ok, _activity} = CommonAPI.favorite(activity.id, user)
      [fetched_vote] = Utils.get_existing_votes(other_user.ap_id, object)
      assert fetched_vote.id == vote.id
    end
  end

  describe "update_follow_state_for_all/2" do
    test "updates the state of all Follow activities with the same actor and object" do
      user = insert(:user, is_locked: true)
      follower = insert(:user)

      {:ok, _, _, follow_activity} = CommonAPI.follow(user, follower)
      {:ok, _, _, follow_activity_two} = CommonAPI.follow(user, follower)

      data =
        follow_activity_two.data
        |> Map.put("state", "accept")

      cng = Ecto.Changeset.change(follow_activity_two, data: data)

      {:ok, follow_activity_two} = Repo.update(cng)

      {:ok, follow_activity_two} =
        Utils.update_follow_state_for_all(follow_activity_two, "accept")

      assert refresh_record(follow_activity).data["state"] == "accept"
      assert refresh_record(follow_activity_two).data["state"] == "accept"
    end

    test "also updates the state of accepted follows" do
      user = insert(:user)
      follower = insert(:user)

      {:ok, _, _, follow_activity} = CommonAPI.follow(user, follower)
      {:ok, _, _, follow_activity_two} = CommonAPI.follow(user, follower)

      {:ok, follow_activity_two} =
        Utils.update_follow_state_for_all(follow_activity_two, "reject")

      assert refresh_record(follow_activity).data["state"] == "reject"
      assert refresh_record(follow_activity_two).data["state"] == "reject"
    end
  end

  describe "update_follow_state/2" do
    test "updates the state of the given follow activity" do
      user = insert(:user, is_locked: true)
      follower = insert(:user)

      {:ok, _, _, follow_activity} = CommonAPI.follow(user, follower)
      {:ok, _, _, follow_activity_two} = CommonAPI.follow(user, follower)

      data =
        follow_activity_two.data
        |> Map.put("state", "accept")

      cng = Ecto.Changeset.change(follow_activity_two, data: data)

      {:ok, follow_activity_two} = Repo.update(cng)

      {:ok, follow_activity_two} = Utils.update_follow_state(follow_activity_two, "reject")

      assert refresh_record(follow_activity).data["state"] == "pending"
      assert refresh_record(follow_activity_two).data["state"] == "reject"
    end
  end

  describe "update_element_in_object/3" do
    test "updates likes" do
      user = insert(:user)
      activity = insert(:note_activity)
      object = Object.normalize(activity, fetch: false)

      assert {:ok, updated_object} =
               Utils.update_element_in_object(
                 "like",
                 [user.ap_id],
                 object
               )

      assert updated_object.data["likes"] == [user.ap_id]
      assert updated_object.data["like_count"] == 1
    end
  end

  describe "add_like_to_object/2" do
    test "add actor to likes" do
      user = insert(:user)
      user2 = insert(:user)
      object = insert(:note)

      assert {:ok, updated_object} =
               Utils.add_like_to_object(
                 %Activity{data: %{"actor" => user.ap_id}},
                 object
               )

      assert updated_object.data["likes"] == [user.ap_id]
      assert updated_object.data["like_count"] == 1

      assert {:ok, updated_object2} =
               Utils.add_like_to_object(
                 %Activity{data: %{"actor" => user2.ap_id}},
                 updated_object
               )

      assert updated_object2.data["likes"] == [user2.ap_id, user.ap_id]
      assert updated_object2.data["like_count"] == 2
    end
  end

  describe "remove_like_from_object/2" do
    test "removes ap_id from likes" do
      user = insert(:user)
      user2 = insert(:user)
      object = insert(:note, data: %{"likes" => [user.ap_id, user2.ap_id], "like_count" => 2})

      assert {:ok, updated_object} =
               Utils.remove_like_from_object(
                 %Activity{data: %{"actor" => user.ap_id}},
                 object
               )

      assert updated_object.data["likes"] == [user2.ap_id]
      assert updated_object.data["like_count"] == 1
    end
  end

  describe "get_existing_like/2" do
    test "fetches existing like" do
      note_activity = insert(:note_activity)
      assert object = Object.normalize(note_activity, fetch: false)

      user = insert(:user)
      refute Utils.get_existing_like(user.ap_id, object)
      {:ok, like_activity} = CommonAPI.favorite(note_activity.id, user)

      assert ^like_activity = Utils.get_existing_like(user.ap_id, object)
    end
  end

  describe "get_get_existing_announce/2" do
    test "returns nil if announce not found" do
      actor = insert(:user)
      refute Utils.get_existing_announce(actor.ap_id, %{data: %{"id" => "test"}})
    end

    test "fetches existing announce" do
      note_activity = insert(:note_activity)
      assert object = Object.normalize(note_activity, fetch: false)
      actor = insert(:user)

      {:ok, announce} = CommonAPI.repeat(note_activity.id, actor)
      assert Utils.get_existing_announce(actor.ap_id, object) == announce
    end
  end

  describe "fetch_latest_block/2" do
    test "fetches last block activities" do
      user1 = insert(:user)
      user2 = insert(:user)

      assert {:ok, %Activity{} = _} = CommonAPI.block(user2, user1)
      assert {:ok, %Activity{} = _} = CommonAPI.block(user2, user1)
      assert {:ok, %Activity{} = activity} = CommonAPI.block(user2, user1)

      assert Utils.fetch_latest_block(user1, user2) == activity
    end
  end

  describe "recipient_in_message/3" do
    test "returns true when recipient in `to`" do
      recipient = insert(:user)
      actor = insert(:user)
      assert Utils.recipient_in_message(recipient, actor, %{"to" => recipient.ap_id})

      assert Utils.recipient_in_message(
               recipient,
               actor,
               %{"to" => [recipient.ap_id], "cc" => ""}
             )
    end

    test "returns true when recipient in `cc`" do
      recipient = insert(:user)
      actor = insert(:user)
      assert Utils.recipient_in_message(recipient, actor, %{"cc" => recipient.ap_id})

      assert Utils.recipient_in_message(
               recipient,
               actor,
               %{"cc" => [recipient.ap_id], "to" => ""}
             )
    end

    test "returns true when recipient in `bto`" do
      recipient = insert(:user)
      actor = insert(:user)
      assert Utils.recipient_in_message(recipient, actor, %{"bto" => recipient.ap_id})

      assert Utils.recipient_in_message(
               recipient,
               actor,
               %{"bcc" => "", "bto" => [recipient.ap_id]}
             )
    end

    test "returns true when recipient in `bcc`" do
      recipient = insert(:user)
      actor = insert(:user)
      assert Utils.recipient_in_message(recipient, actor, %{"bcc" => recipient.ap_id})

      assert Utils.recipient_in_message(
               recipient,
               actor,
               %{"bto" => "", "bcc" => [recipient.ap_id]}
             )
    end

    test "returns true when message without addresses fields" do
      recipient = insert(:user)
      actor = insert(:user)
      assert Utils.recipient_in_message(recipient, actor, %{"bccc" => recipient.ap_id})

      assert Utils.recipient_in_message(
               recipient,
               actor,
               %{"btod" => "", "bccc" => [recipient.ap_id]}
             )
    end

    test "returns false" do
      recipient = insert(:user)
      actor = insert(:user)
      refute Utils.recipient_in_message(recipient, actor, %{"to" => "ap_id"})
    end
  end

  describe "lazy_put_activity_defaults/2" do
    test "returns map with id and published data" do
      note_activity = insert(:note_activity)
      object = Object.normalize(note_activity, fetch: false)
      res = Utils.lazy_put_activity_defaults(%{"context" => object.data["id"]})
      assert res["context"] == object.data["id"]
      assert res["id"]
      assert res["published"]
    end

    test "returns map with fake id and published data" do
      assert %{
               "context" => "pleroma:fakecontext",
               "id" => "pleroma:fakeid",
               "published" => _
             } = Utils.lazy_put_activity_defaults(%{}, true)
    end

    test "returns activity data with object" do
      note_activity = insert(:note_activity)
      object = Object.normalize(note_activity, fetch: false)

      res =
        Utils.lazy_put_activity_defaults(%{
          "context" => object.data["id"],
          "object" => %{}
        })

      assert res["context"] == object.data["id"]
      assert res["id"]
      assert res["published"]
      assert res["object"]["id"]
      assert res["object"]["published"]
      assert res["object"]["context"] == object.data["id"]
    end
  end

  describe "make_flag_data" do
    test "returns empty map when params is invalid" do
      assert Utils.make_flag_data(%{}, %{}) == %{}
    end

    test "returns map with Flag object" do
      reporter = insert(:user)
      target_account = insert(:user)
      {:ok, activity} = CommonAPI.post(target_account, %{status: "foobar"})
      context = Utils.generate_context_id()
      content = "foobar"

      target_ap_id = target_account.ap_id
      object_ap_id = activity.object.data["id"]

      res =
        Utils.make_flag_data(
          %{
            actor: reporter,
            context: context,
            account: target_account,
            statuses: [%{"id" => activity.data["id"]}],
            content: content
          },
          %{}
        )

      note_obj = %{
        "type" => "Note",
        "id" => object_ap_id,
        "content" => content,
        "published" => activity.object.data["published"],
        "actor" =>
          AccountView.render("show.json", %{user: target_account, skip_visibility_check: true})
      }

      assert %{
               "type" => "Flag",
               "content" => ^content,
               "context" => ^context,
               "object" => [^target_ap_id, ^note_obj],
               "state" => "open"
             } = res
    end

    test "returns map with Flag object with a non-Create Activity" do
      reporter = insert(:user)
      posting_account = insert(:user)
      target_account = insert(:user)

      {:ok, activity} = CommonAPI.post(posting_account, %{status: "foobar"})
      {:ok, like} = CommonAPI.favorite(activity.id, target_account)
      context = Utils.generate_context_id()
      content = "foobar"

      target_ap_id = target_account.ap_id
      object_ap_id = activity.object.data["id"]

      res =
        Utils.make_flag_data(
          %{
            actor: reporter,
            context: context,
            account: target_account,
            statuses: [%{"id" => like.data["id"]}],
            content: content
          },
          %{}
        )

      note_obj = %{
        "type" => "Note",
        "id" => object_ap_id,
        "content" => content,
        "published" => activity.object.data["published"],
        "actor" =>
          AccountView.render("show.json", %{user: posting_account, skip_visibility_check: true})
      }

      assert %{
               "type" => "Flag",
               "content" => ^content,
               "context" => ^context,
               "object" => [^target_ap_id, ^note_obj],
               "state" => "open"
             } = res
    end
  end

  describe "add_announce_to_object/2" do
    test "adds actor to announcement" do
      user = insert(:user)
      object = insert(:note)

      activity =
        insert(:note_activity,
          data: %{
            "actor" => user.ap_id,
            "cc" => [Pleroma.Constants.as_public()]
          }
        )

      assert {:ok, updated_object} = Utils.add_announce_to_object(activity, object)
      assert updated_object.data["announcements"] == [user.ap_id]
      assert updated_object.data["announcement_count"] == 1
    end
  end

  describe "remove_announce_from_object/2" do
    test "removes actor from announcements" do
      user = insert(:user)
      user2 = insert(:user)

      object =
        insert(:note,
          data: %{"announcements" => [user.ap_id, user2.ap_id], "announcement_count" => 2}
        )

      activity = insert(:note_activity, data: %{"actor" => user.ap_id})

      assert {:ok, updated_object} = Utils.remove_announce_from_object(activity, object)
      assert updated_object.data["announcements"] == [user2.ap_id]
      assert updated_object.data["announcement_count"] == 1
    end
  end

  describe "get_cached_emoji_reactions/1" do
    test "returns the normalized data or an empty list" do
      object = insert(:note)
      assert Utils.get_cached_emoji_reactions(object) == []

      object = insert(:note, data: %{"reactions" => [["x", ["lain"]]]})
      assert Utils.get_cached_emoji_reactions(object) == [["x", ["lain"], nil]]

      object = insert(:note, data: %{"reactions" => %{}})
      assert Utils.get_cached_emoji_reactions(object) == []
    end
  end

  describe "add_emoji_reaction_to_object/1" do
    test "works with legacy 2-tuple format" do
      user = insert(:user)
      other_user = insert(:user)
      third_user = insert(:user)

      note =
        insert(:note,
          user: user,
          data: %{
            "reactions" => [["😿", [other_user.ap_id]]]
          }
        )

      _activity = insert(:note_activity, user: user, note: note)

      Utils.add_emoji_reaction_to_object(
        %Activity{data: %{"content" => "😿", "actor" => third_user.ap_id}},
        note
      )
    end
  end
end
