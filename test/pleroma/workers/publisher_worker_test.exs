# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.PublisherWorkerTest do
  use Pleroma.DataCase, async: true
  use Oban.Testing, repo: Pleroma.Repo

  import Pleroma.Factory
  import Mock

  alias Pleroma.Instances
  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Builder
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.Federator

  describe "Oban job priority:" do
    setup do
      user = insert(:user)

      {:ok, post} = CommonAPI.post(user, %{status: "Regrettable post"})
      object = Object.normalize(post, fetch: false)
      {:ok, delete_data, _meta} = Builder.delete(user, object.data["id"])
      {:ok, delete, _meta} = ActivityPub.persist(delete_data, local: true)

      %{
        post: post,
        delete: delete
      }
    end

    test "Deletions are lower priority", %{delete: delete} do
      assert {:ok, %Oban.Job{priority: 3}} = Federator.publish(delete)
    end

    test "Creates are normal priority", %{post: post} do
      assert {:ok, %Oban.Job{priority: 0}} = Federator.publish(post)
    end
  end

  describe "Server reachability:" do
    setup do
      user = insert(:user)
      remote_user = insert(:user, local: false, inbox: "https://example.com/inbox")
      {:ok, _, _} = Pleroma.User.follow(remote_user, user)
      {:ok, activity} = CommonAPI.post(user, %{status: "Test post"})

      %{
        user: user,
        remote_user: remote_user,
        activity: activity
      }
    end

    test "marks server as unreachable only on final failure", %{activity: activity} do
      with_mock Pleroma.Web.Federator,
        perform: fn :publish_one, _params -> {:error, :connection_error} end do
        # First attempt
        job = %Oban.Job{
          args: %{
            "op" => "publish_one",
            "params" => %{
              "inbox" => "https://example.com/inbox",
              "activity_id" => activity.id
            }
          },
          attempt: 1,
          max_attempts: 5
        }

        assert {:error, :connection_error} = Pleroma.Workers.PublisherWorker.perform(job)
        assert Instances.reachable?("https://example.com/inbox")

        # Final attempt
        job = %{job | attempt: 5}
        assert {:error, :connection_error} = Pleroma.Workers.PublisherWorker.perform(job)
        refute Instances.reachable?("https://example.com/inbox")
      end
    end

    test "does not mark server as unreachable on successful publish", %{activity: activity} do
      with_mock Pleroma.Web.Federator,
        perform: fn :publish_one, _params -> {:ok, %{status: 200}} end do
        job = %Oban.Job{
          args: %{
            "op" => "publish_one",
            "params" => %{
              "inbox" => "https://example.com/inbox",
              "activity_id" => activity.id
            }
          },
          attempt: 1,
          max_attempts: 5
        }

        assert :ok = Pleroma.Workers.PublisherWorker.perform(job)
        assert Instances.reachable?("https://example.com/inbox")
      end
    end

    test "cancels job if server is unreachable", %{activity: activity} do
      # First mark the server as unreachable
      Instances.set_unreachable("https://example.com/inbox")
      refute Instances.reachable?("https://example.com/inbox")

      job = %Oban.Job{
        args: %{
          "op" => "publish_one",
          "params" => %{
            "inbox" => "https://example.com/inbox",
            "activity_id" => activity.id
          }
        },
        attempt: 1,
        max_attempts: 5
      }

      assert {:cancel, :unreachable} = Pleroma.Workers.PublisherWorker.perform(job)
    end
  end
end
