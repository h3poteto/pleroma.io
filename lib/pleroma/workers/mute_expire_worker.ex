# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.MuteExpireWorker do
  use Oban.Worker, queue: :background

  alias Pleroma.User

  @impl true
  def perform(%Job{
        args: %{"op" => "unmute_user", "muter_id" => muter_id, "mutee_id" => mutee_id}
      }) do
    User.unmute(muter_id, mutee_id)
    :ok
  end

  def perform(%Job{
        args: %{"op" => "unmute_conversation", "user_id" => user_id, "activity_id" => activity_id}
      }) do
    Pleroma.Web.CommonAPI.remove_mute(activity_id, user_id)
    :ok
  end

  def perform(%Job{
        args: %{"op" => "unblock_user", "blocker_id" => blocker_id, "blocked_id" => blocked_id}
      }) do
    Pleroma.Web.CommonAPI.unblock(
      User.get_cached_by_id(blocked_id),
      User.get_cached_by_id(blocker_id)
    )

    :ok
  end

  @impl true
  def timeout(_job), do: :timer.seconds(5)
end
