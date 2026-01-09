# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.DeleteWorkerTest do
  use Pleroma.DataCase, async: true
  use Oban.Testing, repo: Pleroma.Repo

  import Pleroma.Factory

  alias Pleroma.Instances.Instance
  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.Workers.DeleteWorker

  describe "instance deletion" do
    test "creates individual Oban jobs for each user when deleting an instance" do
      user1 = insert(:user, nickname: "alice@example.com", name: "Alice")
      user2 = insert(:user, nickname: "bob@example.com", name: "Bob")

      {:ok, job} = Instance.delete("example.com")

      assert_enqueued(
        worker: DeleteWorker,
        args: %{"op" => "delete_instance", "host" => "example.com"}
      )

      {:ok, :ok} = ObanHelpers.perform(job)

      delete_user_jobs = all_enqueued(worker: DeleteWorker, args: %{"op" => "delete_user"})

      assert length(delete_user_jobs) == 2

      user_ids = [user1.id, user2.id]
      job_user_ids = Enum.map(delete_user_jobs, fn job -> job.args["user_id"] end)

      assert Enum.sort(user_ids) == Enum.sort(job_user_ids)
    end
  end
end
