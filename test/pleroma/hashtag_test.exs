# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HashtagTest do
  use Pleroma.DataCase

  alias Pleroma.Hashtag

  describe "changeset validations" do
    test "ensure non-blank :name" do
      changeset = Hashtag.changeset(%Hashtag{}, %{name: ""})

      assert {:name, {"can't be blank", [validation: :required]}} in changeset.errors
    end
  end

  describe "search_hashtags" do
    test "searches hashtags by partial match" do
      {:ok, _} = Hashtag.get_or_create_by_name("car")
      {:ok, _} = Hashtag.get_or_create_by_name("racecar")
      {:ok, _} = Hashtag.get_or_create_by_name("nascar")
      {:ok, _} = Hashtag.get_or_create_by_name("bicycle")

      results = Hashtag.search("car")
      assert "car" in results
      assert "racecar" in results
      assert "nascar" in results
      refute "bicycle" in results

      results = Hashtag.search("race")
      assert "racecar" in results
      refute "car" in results
      refute "nascar" in results
      refute "bicycle" in results

      results = Hashtag.search("nonexistent")
      assert results == []
    end

    test "searches hashtags by multiple words in query" do
      {:ok, _} = Hashtag.get_or_create_by_name("computer")
      {:ok, _} = Hashtag.get_or_create_by_name("laptop")
      {:ok, _} = Hashtag.get_or_create_by_name("desktop")
      {:ok, _} = Hashtag.get_or_create_by_name("phone")

      # Search for "new computer" - should return "computer"
      results = Hashtag.search("new computer")
      assert "computer" in results
      refute "laptop" in results
      refute "desktop" in results
      refute "phone" in results

      # Search for "computer laptop" - should return both
      results = Hashtag.search("computer laptop")
      assert "computer" in results
      assert "laptop" in results
      refute "desktop" in results
      refute "phone" in results

      # Search for "new phone" - should return "phone"
      results = Hashtag.search("new phone")
      assert "phone" in results
      refute "computer" in results
      refute "laptop" in results
      refute "desktop" in results
    end

    test "supports pagination" do
      {:ok, _} = Hashtag.get_or_create_by_name("alpha")
      {:ok, _} = Hashtag.get_or_create_by_name("beta")
      {:ok, _} = Hashtag.get_or_create_by_name("gamma")
      {:ok, _} = Hashtag.get_or_create_by_name("delta")

      results = Hashtag.search("a", limit: 2)
      assert length(results) == 2

      results = Hashtag.search("a", limit: 2, offset: 1)
      assert length(results) == 2
    end

    test "handles matching many search terms" do
      {:ok, _} = Hashtag.get_or_create_by_name("computer")
      {:ok, _} = Hashtag.get_or_create_by_name("laptop")
      {:ok, _} = Hashtag.get_or_create_by_name("phone")
      {:ok, _} = Hashtag.get_or_create_by_name("tablet")

      results = Hashtag.search("new fast computer laptop phone tablet device")
      assert "computer" in results
      assert "laptop" in results
      assert "phone" in results
      assert "tablet" in results
    end

    test "ranks results by match quality" do
      {:ok, _} = Hashtag.get_or_create_by_name("my_computer")
      {:ok, _} = Hashtag.get_or_create_by_name("computer_science")
      {:ok, _} = Hashtag.get_or_create_by_name("computer")

      results = Hashtag.search("computer")

      # Exact match first
      assert Enum.at(results, 0) == "computer"

      # Prefix match would be next
      assert Enum.at(results, 1) == "computer_science"

      # worst match is last
      assert Enum.at(results, 2) == "my_computer"
    end

    test "prioritizes shorter names when ranking is equal" do
      # Create hashtags with same ranking but different lengths
      {:ok, _} = Hashtag.get_or_create_by_name("car")
      {:ok, _} = Hashtag.get_or_create_by_name("racecar")
      {:ok, _} = Hashtag.get_or_create_by_name("nascar")

      # Search for "car" - shorter names should come first
      results = Hashtag.search("car")
      # Shortest exact match first
      assert Enum.at(results, 0) == "car"
      assert "racecar" in results
      assert "nascar" in results
    end

    test "handles hashtag symbols in search query" do
      {:ok, _} = Hashtag.get_or_create_by_name("computer")
      {:ok, _} = Hashtag.get_or_create_by_name("laptop")
      {:ok, _} = Hashtag.get_or_create_by_name("phone")

      results_with_hash = Hashtag.search("#computer #laptop")
      results_without_hash = Hashtag.search("computer laptop")

      assert results_with_hash == results_without_hash

      results_mixed = Hashtag.search("#computer laptop #phone")
      assert "computer" in results_mixed
      assert "laptop" in results_mixed
      assert "phone" in results_mixed

      results_only_hash = Hashtag.search("#computer")
      results_no_hash = Hashtag.search("computer")
      assert results_only_hash == results_no_hash
    end
  end
end
