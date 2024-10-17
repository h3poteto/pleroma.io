# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.ScheduledActivityTest do
  use Pleroma.DataCase, async: true

  alias Pleroma.ScheduledActivity
  alias Pleroma.Test.StaticConfig
  alias Pleroma.UnstubbedConfigMock, as: ConfigMock

  import Mox
  import Pleroma.Factory

  describe "creation" do
    test "scheduled activities with jobs when ScheduledActivity enabled" do
      ConfigMock
      |> stub(:get, fn
        [ScheduledActivity, :enabled] -> true
        path -> StaticConfig.get(path)
      end)

      user = insert(:user)

      today =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(:timer.minutes(6), :millisecond)
        |> NaiveDateTime.to_iso8601()

      attrs = %{params: %{}, scheduled_at: today}
      {:ok, sa1} = ScheduledActivity.create(user, attrs)
      {:ok, sa2} = ScheduledActivity.create(user, attrs)

      jobs = Repo.all(from(j in Oban.Job, where: j.queue == "federator_outgoing", select: j.args))

      assert jobs == [%{"activity_id" => sa1.id}, %{"activity_id" => sa2.id}]
    end

    test "scheduled activities without jobs when ScheduledActivity disabled" do
      ConfigMock
      |> stub(:get, fn
        [ScheduledActivity, :enabled] -> false
        path -> StaticConfig.get(path)
      end)

      user = insert(:user)

      today =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(:timer.minutes(6), :millisecond)
        |> NaiveDateTime.to_iso8601()

      attrs = %{params: %{}, scheduled_at: today}
      {:ok, _sa1} = ScheduledActivity.create(user, attrs)
      {:ok, _sa2} = ScheduledActivity.create(user, attrs)

      jobs =
        Repo.all(from(j in Oban.Job, where: j.queue == "scheduled_activities", select: j.args))

      assert jobs == []
    end

    test "when daily user limit is exceeded" do
      ConfigMock
      |> stub_with(StaticConfig)

      user = insert(:user)

      today =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(:timer.minutes(6), :millisecond)
        |> NaiveDateTime.to_iso8601()

      attrs = %{params: %{}, scheduled_at: today}
      {:ok, _} = ScheduledActivity.create(user, attrs)
      {:ok, _} = ScheduledActivity.create(user, attrs)

      {:error, changeset} = ScheduledActivity.create(user, attrs)
      assert changeset.errors == [scheduled_at: {"daily limit exceeded", []}]
    end

    test "when total user limit is exceeded" do
      ConfigMock
      |> stub_with(StaticConfig)

      user = insert(:user)

      today =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(:timer.minutes(6), :millisecond)
        |> NaiveDateTime.to_iso8601()

      tomorrow =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(:timer.hours(36), :millisecond)
        |> NaiveDateTime.to_iso8601()

      {:ok, _} = ScheduledActivity.create(user, %{params: %{}, scheduled_at: today})
      {:ok, _} = ScheduledActivity.create(user, %{params: %{}, scheduled_at: today})
      {:ok, _} = ScheduledActivity.create(user, %{params: %{}, scheduled_at: tomorrow})
      {:error, changeset} = ScheduledActivity.create(user, %{params: %{}, scheduled_at: tomorrow})
      assert changeset.errors == [scheduled_at: {"total limit exceeded", []}]
    end

    test "when scheduled_at is earlier than 5 minute from now" do
      ConfigMock
      |> stub_with(StaticConfig)

      user = insert(:user)

      scheduled_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(:timer.minutes(4), :millisecond)
        |> NaiveDateTime.to_iso8601()

      attrs = %{params: %{}, scheduled_at: scheduled_at}
      {:error, changeset} = ScheduledActivity.create(user, attrs)
      assert changeset.errors == [scheduled_at: {"must be at least 5 minutes from now", []}]
    end
  end
end
