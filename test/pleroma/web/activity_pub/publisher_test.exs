# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.PublisherTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.Web.ConnCase

  import ExUnit.CaptureLog
  import Pleroma.Factory
  import Tesla.Mock
  import Mock

  alias Pleroma.Activity
  alias Pleroma.Instances
  alias Pleroma.Object
  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.Web.ActivityPub.Publisher
  alias Pleroma.Web.CommonAPI

  @as_public "https://www.w3.org/ns/activitystreams#Public"

  setup do
    mock(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  setup_all do: clear_config([:instance, :federating], true)

  describe "should_federate?/1" do
    test "it returns false when the inbox is nil" do
      refute Publisher.should_federate?(nil, false)
      refute Publisher.should_federate?(nil, true)
    end

    test "it returns true when public is true" do
      assert Publisher.should_federate?(false, true)
    end
  end

  describe "gather_webfinger_links/1" do
    test "it returns links" do
      user = insert(:user)

      expected_links = [
        %{"href" => user.ap_id, "rel" => "self", "type" => "application/activity+json"},
        %{
          "href" => user.ap_id,
          "rel" => "self",
          "type" => "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\""
        },
        %{
          "rel" => "http://ostatus.org/schema/1.0/subscribe",
          "template" => "#{Pleroma.Web.Endpoint.url()}/ostatus_subscribe?acct={uri}"
        }
      ]

      assert expected_links == Publisher.gather_webfinger_links(user)
    end
  end

  describe "determine_inbox/2" do
    test "it returns sharedInbox for messages involving as:Public in to" do
      user = insert(:user, %{shared_inbox: "http://example.com/inbox"})

      activity = %Activity{
        data: %{"to" => [@as_public], "cc" => [user.follower_address]}
      }

      assert Publisher.determine_inbox(activity, user) == "http://example.com/inbox"
    end

    test "it returns sharedInbox for messages involving as:Public in cc" do
      user = insert(:user, %{shared_inbox: "http://example.com/inbox"})

      activity = %Activity{
        data: %{"cc" => [@as_public], "to" => [user.follower_address]}
      }

      assert Publisher.determine_inbox(activity, user) == "http://example.com/inbox"
    end

    test "it returns sharedInbox for messages involving multiple recipients in to" do
      user = insert(:user, %{shared_inbox: "http://example.com/inbox"})
      user_two = insert(:user)
      user_three = insert(:user)

      activity = %Activity{
        data: %{"cc" => [], "to" => [user.ap_id, user_two.ap_id, user_three.ap_id]}
      }

      assert Publisher.determine_inbox(activity, user) == "http://example.com/inbox"
    end

    test "it returns sharedInbox for messages involving multiple recipients in cc" do
      user = insert(:user, %{shared_inbox: "http://example.com/inbox"})
      user_two = insert(:user)
      user_three = insert(:user)

      activity = %Activity{
        data: %{"to" => [], "cc" => [user.ap_id, user_two.ap_id, user_three.ap_id]}
      }

      assert Publisher.determine_inbox(activity, user) == "http://example.com/inbox"
    end

    test "it returns sharedInbox for messages involving multiple recipients in total" do
      user =
        insert(:user, %{
          shared_inbox: "http://example.com/inbox",
          inbox: "http://example.com/personal-inbox"
        })

      user_two = insert(:user)

      activity = %Activity{
        data: %{"to" => [user_two.ap_id], "cc" => [user.ap_id]}
      }

      assert Publisher.determine_inbox(activity, user) == "http://example.com/inbox"
    end

    test "it returns inbox for messages involving single recipients in total" do
      user =
        insert(:user, %{
          shared_inbox: "http://example.com/inbox",
          inbox: "http://example.com/personal-inbox"
        })

      activity = %Activity{
        data: %{"to" => [user.ap_id], "cc" => []}
      }

      assert Publisher.determine_inbox(activity, user) == "http://example.com/personal-inbox"
    end
  end

  describe "publish_one/1" do
    test "publish to url with with different ports" do
      inbox80 = "http://42.site/users/nick1/inbox"
      inbox42 = "http://42.site:42/users/nick1/inbox"
      activity = insert(:note_activity)

      mock(fn
        %{method: :post, url: "http://42.site:42/users/nick1/inbox"} ->
          {:ok, %Tesla.Env{status: 200, body: "port 42"}}

        %{method: :post, url: "http://42.site/users/nick1/inbox"} ->
          {:ok, %Tesla.Env{status: 200, body: "port 80"}}
      end)

      _actor = insert(:user)

      assert {:ok, %{body: "port 42"}} =
               Publisher.prepare_one(%{
                 inbox: inbox42,
                 activity_id: activity.id,
                 unreachable_since: true
               })
               |> Publisher.publish_one()

      assert {:ok, %{body: "port 80"}} =
               Publisher.prepare_one(%{
                 inbox: inbox80,
                 activity_id: activity.id,
                 unreachable_since: true
               })
               |> Publisher.publish_one()
    end

    test_with_mock "calls `Instances.set_reachable` on successful federation if `unreachable_since` is set",
                   Instances,
                   [:passthrough],
                   [] do
      _actor = insert(:user)
      inbox = "http://200.site/users/nick1/inbox"
      activity = insert(:note_activity)

      assert {:ok, _} =
               Publisher.prepare_one(%{
                 inbox: inbox,
                 activity_id: activity.id,
                 unreachable_since: NaiveDateTime.utc_now() |> NaiveDateTime.to_string()
               })
               |> Publisher.publish_one()

      assert called(Instances.set_reachable(inbox))
    end

    test_with_mock "does NOT call `Instances.set_reachable` on successful federation if `unreachable_since` is nil",
                   Instances,
                   [:passthrough],
                   [] do
      _actor = insert(:user)
      inbox = "http://200.site/users/nick1/inbox"
      activity = insert(:note_activity)

      assert {:ok, _} =
               Publisher.prepare_one(%{
                 inbox: inbox,
                 activity_id: activity.id,
                 unreachable_since: nil
               })
               |> Publisher.publish_one()

      refute called(Instances.set_reachable(inbox))
    end

    test_with_mock "calls `Instances.set_unreachable` on target inbox on non-2xx HTTP response code",
                   Instances,
                   [:passthrough],
                   [] do
      _actor = insert(:user)
      inbox = "http://404.site/users/nick1/inbox"
      activity = insert(:note_activity)

      assert {:cancel, _} =
               Publisher.prepare_one(%{inbox: inbox, activity_id: activity.id})
               |> Publisher.publish_one()

      assert called(Instances.set_unreachable(inbox))
    end

    test_with_mock "it calls `Instances.set_unreachable` on target inbox on request error of any kind",
                   Instances,
                   [:passthrough],
                   [] do
      _actor = insert(:user)
      inbox = "http://connrefused.site/users/nick1/inbox"
      activity = insert(:note_activity)

      assert capture_log(fn ->
               assert {:error, _} =
                        Publisher.prepare_one(%{
                          inbox: inbox,
                          activity_id: activity.id
                        })
                        |> Publisher.publish_one()
             end) =~ "connrefused"

      assert called(Instances.set_unreachable(inbox))
    end

    test_with_mock "does NOT call `Instances.set_unreachable` if target is reachable",
                   Instances,
                   [:passthrough],
                   [] do
      _actor = insert(:user)
      inbox = "http://200.site/users/nick1/inbox"
      activity = insert(:note_activity)

      assert {:ok, _} =
               Publisher.prepare_one(%{inbox: inbox, activity_id: activity.id})
               |> Publisher.publish_one()

      refute called(Instances.set_unreachable(inbox))
    end

    test_with_mock "does NOT call `Instances.set_unreachable` if target instance has non-nil `unreachable_since`",
                   Instances,
                   [:passthrough],
                   [] do
      _actor = insert(:user)
      inbox = "http://connrefused.site/users/nick1/inbox"
      activity = insert(:note_activity)

      assert capture_log(fn ->
               assert {:error, _} =
                        Publisher.prepare_one(%{
                          inbox: inbox,
                          activity_id: activity.id,
                          unreachable_since: NaiveDateTime.utc_now() |> NaiveDateTime.to_string()
                        })
                        |> Publisher.publish_one()
             end) =~ "connrefused"

      refute called(Instances.set_unreachable(inbox))
    end
  end

  describe "publish/2" do
    test_with_mock "doesn't publish a non-public activity to quarantined instances.",
                   Pleroma.Web.ActivityPub.Publisher,
                   [:passthrough],
                   [] do
      Config.put([:instance, :quarantined_instances], [{"domain.com", "some reason"}])

      follower =
        insert(:user, %{
          local: false,
          inbox: "https://domain.com/users/nick1/inbox"
        })

      actor = insert(:user, follower_address: follower.ap_id)

      {:ok, follower, actor} = Pleroma.User.follow(follower, actor)
      actor = refresh_record(actor)

      note_activity =
        insert(:followers_only_note_activity,
          user: actor,
          recipients: [follower.ap_id]
        )

      res = Publisher.publish(actor, note_activity)

      assert res == :ok

      refute_enqueued(
        worker: "Pleroma.Workers.PublisherWorker",
        args: %{
          "params" => %{
            inbox: "https://domain.com/users/nick1/inbox",
            activity_id: note_activity.id
          }
        }
      )
    end

    test_with_mock "Publishes a non-public activity to non-quarantined instances.",
                   Pleroma.Web.ActivityPub.Publisher,
                   [:passthrough],
                   [] do
      Config.put([:instance, :quarantined_instances], [{"somedomain.com", "some reason"}])

      follower =
        insert(:user, %{
          local: false,
          inbox: "https://domain.com/users/nick1/inbox"
        })

      actor = insert(:user, follower_address: follower.ap_id)

      {:ok, follower, actor} = Pleroma.User.follow(follower, actor)
      actor = refresh_record(actor)

      note_activity =
        insert(:followers_only_note_activity,
          user: actor,
          recipients: [follower.ap_id]
        )

      res = Publisher.publish(actor, note_activity)

      assert res == :ok

      assert_enqueued(
        worker: "Pleroma.Workers.PublisherWorker",
        args: %{
          "params" => %{
            inbox: "https://domain.com/users/nick1/inbox",
            activity_id: note_activity.id
          }
        },
        priority: 1
      )
    end

    test_with_mock "Publishes to directly addressed actors with higher priority.",
                   Pleroma.Web.ActivityPub.Publisher,
                   [:passthrough],
                   [] do
      note_activity = insert(:direct_note_activity)

      actor = Pleroma.User.get_by_ap_id(note_activity.data["actor"])

      res = Publisher.publish(actor, note_activity)

      assert res == :ok

      assert called(
               Publisher.enqueue_one(
                 %{
                   inbox: :_,
                   activity_id: note_activity.id
                 },
                 priority: 0
               )
             )
    end

    test_with_mock "publishes an activity with BCC to all relevant peers.",
                   Pleroma.Web.ActivityPub.Publisher,
                   [:passthrough],
                   [] do
      follower =
        insert(:user, %{
          local: false,
          inbox: "https://domain.com/users/nick1/inbox"
        })

      actor = insert(:user, follower_address: follower.ap_id)
      user = insert(:user)

      {:ok, follower, actor} = Pleroma.User.follow(follower, actor)

      note_activity =
        insert(:note_activity,
          recipients: [follower.ap_id],
          data_attrs: %{"bcc" => [user.ap_id]}
        )

      res = Publisher.publish(actor, note_activity)
      assert res == :ok

      assert_enqueued(
        worker: "Pleroma.Workers.PublisherWorker",
        args: %{
          "params" => %{
            inbox: "https://domain.com/users/nick1/inbox",
            activity_id: note_activity.id
          }
        }
      )
    end

    test_with_mock "publishes a delete activity to peers who signed fetch requests to the create acitvity/object.",
                   Pleroma.Web.ActivityPub.Publisher,
                   [:passthrough],
                   [] do
      fetcher =
        insert(:user,
          local: false,
          inbox: "https://domain.com/users/nick1/inbox"
        )

      another_fetcher =
        insert(:user,
          local: false,
          inbox: "https://domain2.com/users/nick1/inbox"
        )

      actor = insert(:user)

      note_activity = insert(:note_activity, user: actor)
      object = Object.normalize(note_activity, fetch: false)

      activity_path = String.trim_leading(note_activity.data["id"], Pleroma.Web.Endpoint.url())
      object_path = String.trim_leading(object.data["id"], Pleroma.Web.Endpoint.url())

      build_conn()
      |> put_req_header("accept", "application/activity+json")
      |> assign(:user, fetcher)
      |> get(object_path)
      |> json_response(200)

      build_conn()
      |> put_req_header("accept", "application/activity+json")
      |> assign(:user, another_fetcher)
      |> get(activity_path)
      |> json_response(200)

      {:ok, delete} = CommonAPI.delete(note_activity.id, actor)

      res = Publisher.publish(actor, delete)
      assert res == :ok

      assert_enqueued(
        worker: "Pleroma.Workers.PublisherWorker",
        args: %{
          "params" => %{
            inbox: "https://domain.com/users/nick1/inbox",
            activity_id: delete.id
          }
        },
        priority: 1
      )

      assert_enqueued(
        worker: "Pleroma.Workers.PublisherWorker",
        args: %{
          "params" => %{
            inbox: "https://domain2.com/users/nick1/inbox",
            activity_id: delete.id
          }
        },
        priority: 1
      )
    end
  end

  test "cc in prepared json for a follow request is an empty list" do
    user = insert(:user)
    remote_user = insert(:user, local: false)

    {:ok, _, _, activity} = CommonAPI.follow(remote_user, user)

    assert_enqueued(
      worker: "Pleroma.Workers.PublisherWorker",
      args: %{
        "activity_id" => activity.id,
        "op" => "publish"
      }
    )

    ObanHelpers.perform_all()

    expected_params =
      %{
        "activity_id" => activity.id,
        "inbox" => remote_user.inbox,
        "unreachable_since" => nil
      }

    assert_enqueued(
      worker: "Pleroma.Workers.PublisherWorker",
      args: %{
        "op" => "publish_one",
        "params" => expected_params
      }
    )

    # params need to be atom keys for Publisher.prepare_one.
    # this is done in the Oban job.
    expected_params = Map.new(expected_params, fn {k, v} -> {String.to_atom(k), v} end)

    %{json: json} = Publisher.prepare_one(expected_params)

    {:ok, decoded} = Jason.decode(json)

    assert decoded["cc"] == []
  end
end
