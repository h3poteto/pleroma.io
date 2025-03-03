# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ObjectValidators.FollowValidationTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.Web.ActivityPub.Builder
  alias Pleroma.Web.ActivityPub.ObjectValidator

  import Pleroma.Factory

  describe "Follows" do
    setup do
      follower = insert(:user)
      followed = insert(:user)

      {:ok, valid_follow, []} = Builder.follow(follower, followed)
      %{follower: follower, followed: followed, valid_follow: valid_follow}
    end

    test "validates a basic follow object", %{valid_follow: valid_follow} do
      assert {:ok, _follow, []} = ObjectValidator.validate(valid_follow, [])
    end

    test "supports a nil cc", %{valid_follow: valid_follow} do
      valid_follow_with_nil_cc = Map.put(valid_follow, "cc", nil)
      assert {:ok, _follow, []} = ObjectValidator.validate(valid_follow_with_nil_cc, [])
    end

    test "supports an empty cc", %{valid_follow: valid_follow} do
      valid_follow_with_empty_cc = Map.put(valid_follow, "cc", [])
      assert {:ok, _follow, []} = ObjectValidator.validate(valid_follow_with_empty_cc, [])
    end
  end
end
