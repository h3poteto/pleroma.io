# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier.LikeHandlingTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  test "it works for incoming likes" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{status: "hello"})

    data =
      File.read!("test/fixtures/mastodon-like.json")
      |> Jason.decode!()
      |> Map.put("object", activity.data["object"])

    _actor = insert(:user, ap_id: data["actor"], local: false)

    {:ok, %Activity{data: data, local: false} = activity} = Transmogrifier.handle_incoming(data)

    refute Enum.empty?(activity.recipients)

    assert data["actor"] == "http://mastodon.example.org/users/admin"
    assert data["type"] == "Like"
    assert data["id"] == "http://mastodon.example.org/users/admin#likes/2"
    assert data["object"] == activity.data["object"]
  end

  test "it works for incoming misskey likes, turning them into EmojiReacts" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{status: "hello"})

    data =
      File.read!("test/fixtures/misskey-like.json")
      |> Jason.decode!()
      |> Map.put("object", activity.data["object"])

    _actor = insert(:user, ap_id: data["actor"], local: false)

    {:ok, %Activity{data: activity_data, local: false}} = Transmogrifier.handle_incoming(data)

    assert activity_data["actor"] == data["actor"]
    assert activity_data["type"] == "EmojiReact"
    assert activity_data["id"] == data["id"]
    assert activity_data["object"] == activity.data["object"]
    assert activity_data["content"] == "🍮"
  end

  test "it works for incoming misskey likes that contain unicode emojis, turning them into EmojiReacts" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{status: "hello"})

    data =
      File.read!("test/fixtures/misskey-like.json")
      |> Jason.decode!()
      |> Map.put("object", activity.data["object"])
      |> Map.put("_misskey_reaction", "⭐")

    _actor = insert(:user, ap_id: data["actor"], local: false)

    {:ok, %Activity{data: activity_data, local: false}} = Transmogrifier.handle_incoming(data)

    assert activity_data["actor"] == data["actor"]
    assert activity_data["type"] == "EmojiReact"
    assert activity_data["id"] == data["id"]
    assert activity_data["object"] == activity.data["object"]
    assert activity_data["content"] == "⭐"
  end

  test "it works for misskey likes with custom emoji" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{status: "hello"})

    data =
      File.read!("test/fixtures/misskey-custom-emoji-like.json")
      |> Jason.decode!()
      |> Map.put("object", activity.data["object"])

    _actor = insert(:user, ap_id: data["actor"], local: false)

    {:ok, %Activity{data: activity_data, local: false}} = Transmogrifier.handle_incoming(data)

    assert activity_data["actor"] == data["actor"]
    assert activity_data["type"] == "EmojiReact"
    assert activity_data["id"] == data["id"]
    assert activity_data["object"] == activity.data["object"]
    assert activity_data["content"] == ":blobwtfnotlikethis:"

    assert [["blobwtfnotlikethis", _, _]] =
             Object.get_by_ap_id(activity.data["object"])
             |> Object.get_emoji_reactions()
  end

  test "it works for mitra likes with custom emoji" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{status: "hello"})

    data =
      File.read!("test/fixtures/mitra-custom-emoji-like.json")
      |> Jason.decode!()
      |> Map.put("object", activity.data["object"])

    _actor = insert(:user, ap_id: data["actor"], local: false)

    {:ok, %Activity{data: activity_data, local: false}} = Transmogrifier.handle_incoming(data)

    assert activity_data["actor"] == data["actor"]
    assert activity_data["type"] == "EmojiReact"
    assert activity_data["id"] == data["id"]
    assert activity_data["object"] == activity.data["object"]
    assert activity_data["content"] == ":ablobcatheartsqueeze:"

    assert [["ablobcatheartsqueeze", _, _]] =
             Object.get_by_ap_id(activity.data["object"])
             |> Object.get_emoji_reactions()
  end

  test "it works for likes with wrong content" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{status: "hello"})

    data =
      File.read!("test/fixtures/mitra-custom-emoji-like.json")
      |> Jason.decode!()
      |> Map.put("object", activity.data["object"])
      |> Map.put("content", 1)

    _actor = insert(:user, ap_id: data["actor"], local: false)

    assert {:ok, activity} = Transmogrifier.handle_incoming(data)
    assert activity.data["type"] == "Like"
  end

  test "it changes incoming dislikes into emoji reactions" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{status: "hello"})

    data =
      File.read!("test/fixtures/friendica-dislike.json")
      |> Jason.decode!()
      |> Map.put("object", activity.data["object"])

    _actor = insert(:user, ap_id: data["actor"], local: false)

    {:ok, %Activity{data: data, local: false} = activity} = Transmogrifier.handle_incoming(data)

    refute Enum.empty?(activity.recipients)

    assert data["actor"] == "https://my-place.social/profile/vaartis"
    assert data["type"] == "EmojiReact"
    assert data["content"] == "👎"
    assert data["id"] == "https://my-place.social/objects/e599373b-1368-4b20-cd24-837166957182"
    assert data["object"] == activity.data["object"]

    data =
      File.read!("test/fixtures/friendica-dislike-undo.json")
      |> Jason.decode!()
      |> put_in(["object", "object"], activity.data["object"])

    {:ok, %Activity{data: data, local: false}} = Transmogrifier.handle_incoming(data)

    assert data["actor"] == "https://my-place.social/profile/vaartis"
    assert data["type"] == "Undo"

    assert data["object"] ==
             "https://my-place.social/objects/e599373b-1368-4b20-cd24-837166957182"
  end
end
