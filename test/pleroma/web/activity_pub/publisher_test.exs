# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.PublisherTest do
  use Oban.Testing, repo: Pleroma.Repo
  use Pleroma.Web.ConnCase

  import Pleroma.Factory
  import Tesla.Mock

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Publisher
  alias Pleroma.Web.ActivityPub.Utils
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
  end

  describe "publish/2" do
    test "doesn't publish a non-public activity to quarantined instances." do
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

    test "Publishes a non-public activity to non-quarantined instances." do
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

    test "Publishes to directly addressed actors with higher priority." do
      note_activity = insert(:direct_note_activity)

      actor = Pleroma.User.get_by_ap_id(note_activity.data["actor"])

      res = Publisher.publish(actor, note_activity)

      assert res == :ok

      assert_enqueued(
        worker: "Pleroma.Workers.PublisherWorker",
        args: %{
          "op" => "publish_one",
          "params" => %{"activity_id" => note_activity.id}
        },
        priority: 0
      )
    end

    test "Publishes with the new actor if prepare_outgoing changes the actor." do
      mock(fn
        %{method: :post, url: "https://domain.com/users/nick1/inbox", body: body} ->
          {:ok, %Tesla.Env{status: 200, body: body}}
      end)

      other_user =
        insert(:user, %{
          local: false,
          inbox: "https://domain.com/users/nick1/inbox"
        })

      actor = insert(:user)
      replaced_actor = insert(:user)

      note_activity =
        insert(:note_activity,
          user: actor,
          data_attrs: %{"to" => [other_user.ap_id]}
        )

      Pleroma.Web.ActivityPub.TransmogrifierMock
      |> Mox.expect(:prepare_outgoing, fn data ->
        {:ok, Map.put(data, "actor", replaced_actor.ap_id)}
      end)

      prepared =
        Publisher.prepare_one(%{
          inbox: "https://domain.com/users/nick1/inbox",
          activity_id: note_activity.id,
          cc: ["https://domain.com/users/nick2/inbox"]
        })

      {:ok, decoded} = Jason.decode(prepared.json)
      assert decoded["actor"] == replaced_actor.ap_id

      {:ok, published} = Publisher.publish_one(prepared)
      sent_activity = Jason.decode!(published.body)
      assert sent_activity["actor"] == replaced_actor.ap_id
    end

    test "publishes an activity with BCC to all relevant peers." do
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

    test "activity with BCC is published to a list member." do
      actor = insert(:user)
      {:ok, list} = Pleroma.List.create("list", actor)
      list_member = insert(:user, %{local: false})

      Pleroma.List.follow(list, list_member)

      note_activity =
        insert(:note_activity,
          # recipients: [follower.ap_id],
          data_attrs: %{"bcc" => [list.ap_id]}
        )

      res = Publisher.publish(actor, note_activity)
      assert res == :ok

      assert_enqueued(
        worker: "Pleroma.Workers.PublisherWorker",
        args: %{
          "params" => %{
            inbox: list_member.inbox,
            activity_id: note_activity.id
          }
        }
      )
    end

    test "publishes a delete activity to peers who signed fetch requests to the create acitvity/object." do
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

  test "unlisted activities retain public address in cc" do
    user = insert(:user)

    # simulate unlistd activity by only having
    # public address in cc
    activity =
      insert(:note_activity,
        user: user,
        data_attrs: %{
          "cc" => [@as_public],
          "to" => [user.follower_address]
        }
      )

    assert @as_public in activity.data["cc"]

    prepared =
      Publisher.prepare_one(%{
        inbox: "https://remote.instance/users/someone/inbox",
        activity_id: activity.id
      })

    {:ok, decoded} = Jason.decode(prepared.json)

    assert @as_public in decoded["cc"]

    # maybe we also have another inbox in cc
    # during Publishing
    activity =
      insert(:note_activity,
        user: user,
        data_attrs: %{
          "cc" => [@as_public],
          "to" => [user.follower_address]
        }
      )

    prepared =
      Publisher.prepare_one(%{
        inbox: "https://remote.instance/users/someone/inbox",
        activity_id: activity.id,
        cc: ["https://remote.instance/users/someone_else/inbox"]
      })

    {:ok, decoded} = Jason.decode(prepared.json)

    assert decoded["cc"] == [@as_public, "https://remote.instance/users/someone_else/inbox"]
  end

  test "public address in cc parameter is preserved" do
    user = insert(:user)

    cc_with_public = [@as_public, "https://example.org/users/other"]

    activity =
      insert(:note_activity,
        user: user,
        data_attrs: %{
          "cc" => cc_with_public,
          "to" => [user.follower_address]
        }
      )

    assert @as_public in activity.data["cc"]

    prepared =
      Publisher.prepare_one(%{
        inbox: "https://remote.instance/users/someone/inbox",
        activity_id: activity.id,
        cc: cc_with_public
      })

    {:ok, decoded} = Jason.decode(prepared.json)

    assert cc_with_public == decoded["cc"]
  end

  test "cc parameter is preserved" do
    user = insert(:user)

    activity =
      insert(:note_activity,
        user: user,
        data_attrs: %{
          "cc" => ["https://example.com/specific/user"],
          "to" => [user.follower_address]
        }
      )

    prepared =
      Publisher.prepare_one(%{
        inbox: "https://remote.instance/users/someone/inbox",
        activity_id: activity.id,
        cc: ["https://example.com/specific/user"]
      })

    {:ok, decoded} = Jason.decode(prepared.json)

    assert decoded["cc"] == ["https://example.com/specific/user"]
  end

  describe "prepare_one/1 with reporter anonymization" do
    test "signs with the anonymized actor keys when Transmogrifier changes actor" do
      Pleroma.SignatureMock
      |> Mox.stub(:signed_date, fn -> Pleroma.Signature.signed_date() end)
      |> Mox.expect(:sign, fn %Pleroma.User{} = user, _headers ->
        send(self(), {:signed_as, user.ap_id})
        "TESTSIG"
      end)

      placeholder = insert(:user)
      reporter = insert(:user)
      target_account = insert(:user)

      clear_config([:activitypub, :anonymize_reporter], true)
      clear_config([:activitypub, :anonymize_reporter_local_nickname], placeholder.nickname)

      {:ok, reported} = CommonAPI.post(target_account, %{status: "content"})
      context = Utils.generate_context_id()

      {:ok, activity} =
        ActivityPub.flag(%{
          actor: reporter,
          context: context,
          account: target_account,
          statuses: [reported],
          content: "reason"
        })

      _prepared =
        Publisher.prepare_one(%{
          inbox: "http://remote.example/users/alice/inbox",
          activity_id: activity.id
        })

      assert_received {:signed_as, ap_id}
      assert ap_id == placeholder.ap_id
    end
  end
end
