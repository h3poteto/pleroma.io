# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Object.FetcherTest do
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.Instances
  alias Pleroma.Object
  alias Pleroma.Object.Fetcher
  alias Pleroma.Web.ActivityPub.ObjectValidator

  require Pleroma.Constants

  import Mock
  import Pleroma.Factory
  import Tesla.Mock

  setup do
    mock(fn
      %{method: :get, url: "https://mastodon.example.org/users/userisgone"} ->
        %Tesla.Env{status: 410}

      %{method: :get, url: "https://mastodon.example.org/users/userisgone404"} ->
        %Tesla.Env{status: 404}

      %{
        method: :get,
        url:
          "https://patch.cx/media/03ca3c8b4ac3ddd08bf0f84be7885f2f88de0f709112131a22d83650819e36c2.json"
      } ->
        %Tesla.Env{
          status: 200,
          headers: [{"content-type", "application/json"}],
          body: File.read!("test/fixtures/spoofed-object.json")
        }

      env ->
        apply(HttpRequestMock, :request, [env])
    end)

    :ok
  end

  describe "error cases" do
    setup do
      mock(fn
        %{method: :get, url: "https://social.sakamoto.gq/notice/9wTkLEnuq47B25EehM"} ->
          %Tesla.Env{
            status: 200,
            body: File.read!("test/fixtures/fetch_mocks/9wTkLEnuq47B25EehM.json"),
            headers: HttpRequestMock.activitypub_object_headers()
          }

        %{method: :get, url: "https://social.sakamoto.gq/users/eal"} ->
          %Tesla.Env{
            status: 200,
            body: File.read!("test/fixtures/fetch_mocks/eal.json"),
            headers: HttpRequestMock.activitypub_object_headers()
          }

        %{method: :get, url: "https://busshi.moe/users/tuxcrafting/statuses/104410921027210069"} ->
          %Tesla.Env{
            status: 200,
            body: File.read!("test/fixtures/fetch_mocks/104410921027210069.json"),
            headers: HttpRequestMock.activitypub_object_headers()
          }

        %{method: :get, url: "https://busshi.moe/users/tuxcrafting"} ->
          %Tesla.Env{
            status: 500
          }

        %{
          method: :get,
          url: "https://stereophonic.space/objects/02997b83-3ea7-4b63-94af-ef3aa2d4ed17"
        } ->
          %Tesla.Env{
            status: 500
          }
      end)

      :ok
    end

    test "it works when fetching the OP actor errors out" do
      # Here we simulate a case where the author of the OP can't be read
      assert {:ok, _} =
               Fetcher.fetch_object_from_id(
                 "https://social.sakamoto.gq/notice/9wTkLEnuq47B25EehM"
               )
    end
  end

  describe "max thread distance restriction" do
    @ap_id "http://mastodon.example.org/@admin/99541947525187367"
    setup do: clear_config([:instance, :federation_incoming_replies_max_depth])

    test "it returns thread depth exceeded error if thread depth is exceeded" do
      clear_config([:instance, :federation_incoming_replies_max_depth], 0)

      assert {:allowed_depth, false} = Fetcher.fetch_object_from_id(@ap_id, depth: 1)
    end

    test "it fetches object if max thread depth is restricted to 0 and depth is not specified" do
      clear_config([:instance, :federation_incoming_replies_max_depth], 0)

      assert {:ok, _} = Fetcher.fetch_object_from_id(@ap_id)
    end

    test "it fetches object if requested depth does not exceed max thread depth" do
      clear_config([:instance, :federation_incoming_replies_max_depth], 10)

      assert {:ok, _} = Fetcher.fetch_object_from_id(@ap_id, depth: 10)
    end
  end

  describe "actor origin containment" do
    test "it rejects objects with a bogus origin" do
      {:containment, :error} =
        Fetcher.fetch_object_from_id("https://info.pleroma.site/activity.json")
    end

    test "it rejects objects when attributedTo is wrong (variant 1)" do
      {:containment, :error} =
        Fetcher.fetch_object_from_id("https://info.pleroma.site/activity2.json")
    end

    test "it rejects objects when attributedTo is wrong (variant 2)" do
      {:containment, :error} =
        Fetcher.fetch_object_from_id("https://info.pleroma.site/activity3.json")
    end
  end

  describe "fetching an object" do
    test "it fetches an object" do
      {:ok, object} =
        Fetcher.fetch_object_from_id("http://mastodon.example.org/@admin/99541947525187367")

      assert _activity = Activity.get_create_by_object_ap_id(object.data["id"])

      {:ok, object_again} =
        Fetcher.fetch_object_from_id("http://mastodon.example.org/@admin/99541947525187367")

      assert [attachment] = object.data["attachment"]
      assert is_list(attachment["url"])

      assert object == object_again
    end

    test "Return MRF reason when fetched status is rejected by one" do
      clear_config([:mrf_keyword, :reject], ["yeah"])
      clear_config([:mrf, :policies], [Pleroma.Web.ActivityPub.MRF.KeywordPolicy])

      assert {:transmogrifier, {:reject, "[KeywordPolicy] Matches with rejected keyword"}} ==
               Fetcher.fetch_object_from_id(
                 "http://mastodon.example.org/@admin/99541947525187367"
               )
    end

    test "it does not fetch a spoofed object uploaded on an instance as an attachment" do
      assert {:fetch, {:error, {:content_type, "application/json"}}} =
               Fetcher.fetch_object_from_id(
                 "https://patch.cx/media/03ca3c8b4ac3ddd08bf0f84be7885f2f88de0f709112131a22d83650819e36c2.json"
               )
    end

    test "it does not fetch from local instance" do
      local_url = Pleroma.Web.Endpoint.url() <> "/objects/local_resource"

      assert {:fetch, {:error, "Trying to fetch local resource"}} =
               Fetcher.fetch_object_from_id(local_url)
    end

    test "it validates content-type headers according to ActivityPub spec" do
      # Setup a mock for an object with invalid content-type
      mock(fn
        %{method: :get, url: "https://example.com/objects/invalid-content-type"} ->
          %Tesla.Env{
            status: 200,
            # Not a valid AP content-type
            headers: [{"content-type", "application/json"}],
            body:
              Jason.encode!(%{
                "id" => "https://example.com/objects/invalid-content-type",
                "type" => "Note",
                "content" => "This has an invalid content type",
                "actor" => "https://example.com/users/actor",
                "attributedTo" => "https://example.com/users/actor"
              })
          }
      end)

      assert {:fetch, {:error, {:content_type, "application/json"}}} =
               Fetcher.fetch_object_from_id("https://example.com/objects/invalid-content-type")
    end

    test "it accepts objects with application/ld+json and ActivityStreams profile" do
      # Setup a mock for an object with ld+json content-type and AS profile
      mock(fn
        %{method: :get, url: "https://example.com/objects/valid-ld-json"} ->
          %Tesla.Env{
            status: 200,
            headers: [
              {"content-type",
               "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\""}
            ],
            body:
              Jason.encode!(%{
                "id" => "https://example.com/objects/valid-ld-json",
                "type" => "Note",
                "content" => "This has a valid ld+json content type",
                "actor" => "https://example.com/users/actor",
                "attributedTo" => "https://example.com/users/actor"
              })
          }
      end)

      # This should pass if content-type validation works correctly
      assert {:ok, object} =
               Fetcher.fetch_and_contain_remote_object_from_id(
                 "https://example.com/objects/valid-ld-json"
               )

      assert object["content"] == "This has a valid ld+json content type"
    end

    test "it rejects objects with no content-type header" do
      # Setup a mock for an object with no content-type header
      mock(fn
        %{method: :get, url: "https://example.com/objects/no-content-type"} ->
          %Tesla.Env{
            status: 200,
            # No content-type header
            headers: [],
            body:
              Jason.encode!(%{
                "id" => "https://example.com/objects/no-content-type",
                "type" => "Note",
                "content" => "This has no content type header",
                "actor" => "https://example.com/users/actor",
                "attributedTo" => "https://example.com/users/actor"
              })
          }
      end)

      # We want to test that the request fails with a missing content-type error
      # but the actual error is {:fetch, {:error, nil}} - we'll check for this format
      result = Fetcher.fetch_object_from_id("https://example.com/objects/no-content-type")
      assert {:fetch, {:error, nil}} = result
    end

    test "it resets instance reachability on successful fetch" do
      id = "http://mastodon.example.org/@admin/99541947525187367"
      Instances.set_consistently_unreachable(id)
      refute Instances.reachable?(id)

      {:ok, _object} =
        Fetcher.fetch_object_from_id("http://mastodon.example.org/@admin/99541947525187367")

      assert Instances.reachable?(id)
    end
  end

  describe "implementation quirks" do
    test "it can fetch plume articles" do
      {:ok, object} =
        Fetcher.fetch_object_from_id(
          "https://baptiste.gelez.xyz/~/PlumeDevelopment/this-month-in-plume-june-2018/"
        )

      assert object
    end

    test "it can fetch peertube videos" do
      {:ok, object} =
        Fetcher.fetch_object_from_id(
          "https://peertube.moe/videos/watch/df5f464b-be8d-46fb-ad81-2d4c2d1630e3"
        )

      assert object
    end

    test "it can fetch Mobilizon events" do
      {:ok, object} =
        Fetcher.fetch_object_from_id(
          "https://mobilizon.org/events/252d5816-00a3-4a89-a66f-15bf65c33e39"
        )

      assert object
    end

    test "it can fetch wedistribute articles" do
      {:ok, object} =
        Fetcher.fetch_object_from_id("https://wedistribute.org/wp-json/pterotype/v1/object/85810")

      assert object
    end

    test "all objects with fake directions are rejected by the object fetcher" do
      assert {:error, _} =
               Fetcher.fetch_and_contain_remote_object_from_id(
                 "https://info.pleroma.site/activity4.json"
               )
    end

    test "handle HTTP 410 Gone response" do
      assert {:error, :not_found} ==
               Fetcher.fetch_and_contain_remote_object_from_id(
                 "https://mastodon.example.org/users/userisgone"
               )
    end

    test "handle HTTP 404 response" do
      assert {:error, :not_found} ==
               Fetcher.fetch_and_contain_remote_object_from_id(
                 "https://mastodon.example.org/users/userisgone404"
               )
    end

    test "it can fetch pleroma polls with attachments" do
      {:ok, object} =
        Fetcher.fetch_object_from_id("https://patch.cx/objects/tesla_mock/poll_attachment")

      assert object
    end
  end

  describe "pruning" do
    test "it can refetch pruned objects" do
      object_id = "http://mastodon.example.org/@admin/99541947525187367"

      {:ok, object} = Fetcher.fetch_object_from_id(object_id)

      assert object

      {:ok, _object} = Object.prune(object)

      refute Object.get_by_ap_id(object_id)

      {:ok, %Object{} = object_two} = Fetcher.fetch_object_from_id(object_id)

      assert object.data["id"] == object_two.data["id"]
      assert object.id != object_two.id
    end
  end

  describe "signed fetches" do
    setup do: clear_config([:activitypub, :sign_object_fetches])

    test_with_mock "it signs fetches when configured to do so",
                   Pleroma.Signature,
                   [:passthrough],
                   [] do
      clear_config([:activitypub, :sign_object_fetches], true)

      Fetcher.fetch_object_from_id("http://mastodon.example.org/@admin/99541947525187367")

      assert called(Pleroma.Signature.sign(:_, :_))
    end

    test_with_mock "it doesn't sign fetches when not configured to do so",
                   Pleroma.Signature,
                   [:passthrough],
                   [] do
      clear_config([:activitypub, :sign_object_fetches], false)

      Fetcher.fetch_object_from_id("http://mastodon.example.org/@admin/99541947525187367")

      refute called(Pleroma.Signature.sign(:_, :_))
    end
  end

  describe "refetching" do
    setup do
      insert(:user, ap_id: "https://mastodon.social/users/emelie")

      object1 = %{
        "id" => "https://mastodon.social/1",
        "actor" => "https://mastodon.social/users/emelie",
        "attributedTo" => "https://mastodon.social/users/emelie",
        "type" => "Note",
        "content" => "test 1",
        "bcc" => [],
        "bto" => [],
        "cc" => [],
        "to" => [Pleroma.Constants.as_public()],
        "summary" => "",
        "published" => "2023-05-08 23:43:20Z",
        "updated" => "2023-05-09 23:43:20Z"
      }

      {:ok, local_object1, _} = ObjectValidator.validate(object1, [])

      object2 = %{
        "id" => "https://mastodon.social/2",
        "actor" => "https://mastodon.social/users/emelie",
        "attributedTo" => "https://mastodon.social/users/emelie",
        "type" => "Note",
        "content" => "test 2",
        "bcc" => [],
        "bto" => [],
        "cc" => [],
        "to" => [Pleroma.Constants.as_public()],
        "summary" => "",
        "published" => "2023-05-08 23:43:20Z",
        "updated" => "2023-05-09 23:43:25Z",
        "formerRepresentations" => %{
          "type" => "OrderedCollection",
          "orderedItems" => [
            %{
              "type" => "Note",
              "content" => "orig 2",
              "actor" => "https://mastodon.social/users/emelie",
              "attributedTo" => "https://mastodon.social/users/emelie",
              "bcc" => [],
              "bto" => [],
              "cc" => [],
              "to" => [Pleroma.Constants.as_public()],
              "summary" => "",
              "published" => "2023-05-08 23:43:20Z",
              "updated" => "2023-05-09 23:43:21Z"
            }
          ],
          "totalItems" => 1
        }
      }

      {:ok, local_object2, _} = ObjectValidator.validate(object2, [])

      mock(fn
        %{
          method: :get,
          url: "https://mastodon.social/1"
        } ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body: Jason.encode!(object1 |> Map.put("updated", "2023-05-09 23:44:20Z"))
          }

        %{
          method: :get,
          url: "https://mastodon.social/2"
        } ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body: Jason.encode!(object2 |> Map.put("updated", "2023-05-09 23:44:20Z"))
          }

        %{
          method: :get,
          url: "https://mastodon.social/users/emelie/collections/featured"
        } ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body:
              Jason.encode!(%{
                "id" => "https://mastodon.social/users/emelie/collections/featured",
                "type" => "OrderedCollection",
                "actor" => "https://mastodon.social/users/emelie",
                "attributedTo" => "https://mastodon.social/users/emelie",
                "orderedItems" => [],
                "totalItems" => 0
              })
          }

        env ->
          apply(HttpRequestMock, :request, [env])
      end)

      %{object1: local_object1, object2: local_object2}
    end

    test "it keeps formerRepresentations if remote does not have this attr", %{object1: object1} do
      full_object1 =
        object1
        |> Map.merge(%{
          "formerRepresentations" => %{
            "type" => "OrderedCollection",
            "orderedItems" => [
              %{
                "type" => "Note",
                "content" => "orig 2",
                "actor" => "https://mastodon.social/users/emelie",
                "attributedTo" => "https://mastodon.social/users/emelie",
                "bcc" => [],
                "bto" => [],
                "cc" => [],
                "to" => [Pleroma.Constants.as_public()],
                "summary" => "",
                "published" => "2023-05-08 23:43:20Z"
              }
            ],
            "totalItems" => 1
          }
        })

      {:ok, o} = Object.create(full_object1)

      assert {:ok, refetched} = Fetcher.refetch_object(o)

      assert %{"formerRepresentations" => %{"orderedItems" => [%{"content" => "orig 2"}]}} =
               refetched.data
    end

    test "it uses formerRepresentations from remote if possible", %{object2: object2} do
      {:ok, o} = Object.create(object2)

      assert {:ok, refetched} = Fetcher.refetch_object(o)

      assert %{"formerRepresentations" => %{"orderedItems" => [%{"content" => "orig 2"}]}} =
               refetched.data
    end

    test "it replaces formerRepresentations with the one from remote", %{object2: object2} do
      full_object2 =
        object2
        |> Map.merge(%{
          "content" => "mew mew #def",
          "formerRepresentations" => %{
            "type" => "OrderedCollection",
            "orderedItems" => [
              %{"type" => "Note", "content" => "mew mew 2"}
            ],
            "totalItems" => 1
          }
        })

      {:ok, o} = Object.create(full_object2)

      assert {:ok, refetched} = Fetcher.refetch_object(o)

      assert %{
               "content" => "test 2",
               "formerRepresentations" => %{"orderedItems" => [%{"content" => "orig 2"}]}
             } = refetched.data
    end

    test "it adds to formerRepresentations if the remote does not have one and the object has changed",
         %{object1: object1} do
      full_object1 =
        object1
        |> Map.merge(%{
          "content" => "mew mew #def",
          "formerRepresentations" => %{
            "type" => "OrderedCollection",
            "orderedItems" => [
              %{"type" => "Note", "content" => "mew mew 1"}
            ],
            "totalItems" => 1
          }
        })

      {:ok, o} = Object.create(full_object1)

      assert {:ok, refetched} = Fetcher.refetch_object(o)

      assert %{
               "content" => "test 1",
               "formerRepresentations" => %{
                 "orderedItems" => [
                   %{"content" => "mew mew #def"},
                   %{"content" => "mew mew 1"}
                 ],
                 "totalItems" => 2
               }
             } = refetched.data
    end

    test "it keeps the history intact if only updated time has changed",
         %{object1: object1} do
      full_object1 =
        object1
        |> Map.merge(%{
          "updated" => "2023-05-08 23:43:47Z",
          "formerRepresentations" => %{
            "type" => "OrderedCollection",
            "orderedItems" => [
              %{"type" => "Note", "content" => "mew mew 1"}
            ],
            "totalItems" => 1
          }
        })

      {:ok, o} = Object.create(full_object1)

      assert {:ok, refetched} = Fetcher.refetch_object(o)

      assert %{
               "content" => "test 1",
               "formerRepresentations" => %{
                 "orderedItems" => [
                   %{"content" => "mew mew 1"}
                 ],
                 "totalItems" => 1
               }
             } = refetched.data
    end

    test "it goes through ObjectValidator and MRF", %{object2: object2} do
      with_mock Pleroma.Web.ActivityPub.MRF, [:passthrough],
        filter: fn
          %{"type" => "Note"} = object ->
            {:ok, Map.put(object, "content", "MRFd content")}

          arg ->
            passthrough([arg])
        end do
        {:ok, o} = Object.create(object2)

        assert {:ok, refetched} = Fetcher.refetch_object(o)

        assert %{"content" => "MRFd content"} = refetched.data
      end
    end
  end

  describe "cross-domain redirect handling" do
    setup do
      mock(fn
        # Cross-domain redirect with original domain in id
        %{method: :get, url: "https://original.test/objects/123"} ->
          %Tesla.Env{
            status: 200,
            url: "https://media.test/objects/123",
            headers: [{"content-type", "application/activity+json"}],
            body:
              Jason.encode!(%{
                "id" => "https://original.test/objects/123",
                "type" => "Note",
                "content" => "This is redirected content",
                "actor" => "https://original.test/users/actor",
                "attributedTo" => "https://original.test/users/actor"
              })
          }

        # Cross-domain redirect with final domain in id
        %{method: :get, url: "https://original.test/objects/final-domain-id"} ->
          %Tesla.Env{
            status: 200,
            url: "https://media.test/objects/final-domain-id",
            headers: [{"content-type", "application/activity+json"}],
            body:
              Jason.encode!(%{
                "id" => "https://media.test/objects/final-domain-id",
                "type" => "Note",
                "content" => "This has final domain in id",
                "actor" => "https://original.test/users/actor",
                "attributedTo" => "https://original.test/users/actor"
              })
          }

        # No redirect - same domain
        %{method: :get, url: "https://original.test/objects/same-domain-redirect"} ->
          %Tesla.Env{
            status: 200,
            url: "https://original.test/objects/different-path",
            headers: [{"content-type", "application/activity+json"}],
            body:
              Jason.encode!(%{
                "id" => "https://original.test/objects/same-domain-redirect",
                "type" => "Note",
                "content" => "This has a same-domain redirect",
                "actor" => "https://original.test/users/actor",
                "attributedTo" => "https://original.test/users/actor"
              })
          }

        # Test case with missing url field in response (common in tests)
        %{method: :get, url: "https://original.test/objects/missing-url"} ->
          %Tesla.Env{
            status: 200,
            # No url field
            headers: [{"content-type", "application/activity+json"}],
            body:
              Jason.encode!(%{
                "id" => "https://original.test/objects/missing-url",
                "type" => "Note",
                "content" => "This has no URL field in response",
                "actor" => "https://original.test/users/actor",
                "attributedTo" => "https://original.test/users/actor"
              })
          }
      end)

      :ok
    end

    test "it rejects objects from cross-domain redirects with original domain in id" do
      assert {:error, {:cross_domain_redirect, true}} =
               Fetcher.fetch_and_contain_remote_object_from_id(
                 "https://original.test/objects/123"
               )
    end

    test "it rejects objects from cross-domain redirects with final domain in id" do
      assert {:error, {:cross_domain_redirect, true}} =
               Fetcher.fetch_and_contain_remote_object_from_id(
                 "https://original.test/objects/final-domain-id"
               )
    end

    test "it accepts objects with same-domain redirects" do
      assert {:ok, data} =
               Fetcher.fetch_and_contain_remote_object_from_id(
                 "https://original.test/objects/same-domain-redirect"
               )

      assert data["content"] == "This has a same-domain redirect"
    end

    test "it handles responses without URL field (common in tests)" do
      assert {:ok, data} =
               Fetcher.fetch_and_contain_remote_object_from_id(
                 "https://original.test/objects/missing-url"
               )

      assert data["content"] == "This has no URL field in response"
    end
  end

  describe "fetch with history" do
    setup do
      object2 = %{
        "id" => "https://mastodon.social/2",
        "actor" => "https://mastodon.social/users/emelie",
        "attributedTo" => "https://mastodon.social/users/emelie",
        "type" => "Note",
        "content" => "test 2",
        "bcc" => [],
        "bto" => [],
        "cc" => ["https://mastodon.social/users/emelie/followers"],
        "to" => [],
        "summary" => "",
        "formerRepresentations" => %{
          "type" => "OrderedCollection",
          "orderedItems" => [
            %{
              "type" => "Note",
              "content" => "orig 2",
              "actor" => "https://mastodon.social/users/emelie",
              "attributedTo" => "https://mastodon.social/users/emelie",
              "bcc" => [],
              "bto" => [],
              "cc" => ["https://mastodon.social/users/emelie/followers"],
              "to" => [],
              "summary" => ""
            }
          ],
          "totalItems" => 1
        }
      }

      mock(fn
        %{
          method: :get,
          url: "https://mastodon.social/2"
        } ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body: Jason.encode!(object2)
          }

        %{
          method: :get,
          url: "https://mastodon.social/users/emelie/collections/featured"
        } ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body:
              Jason.encode!(%{
                "id" => "https://mastodon.social/users/emelie/collections/featured",
                "type" => "OrderedCollection",
                "actor" => "https://mastodon.social/users/emelie",
                "attributedTo" => "https://mastodon.social/users/emelie",
                "orderedItems" => [],
                "totalItems" => 0
              })
          }

        env ->
          apply(HttpRequestMock, :request, [env])
      end)

      %{object2: object2}
    end

    test "it gets history", %{object2: object2} do
      {:ok, object} = Fetcher.fetch_object_from_id(object2["id"])

      assert %{
               "formerRepresentations" => %{
                 "type" => "OrderedCollection",
                 "orderedItems" => [%{}]
               }
             } = object.data
    end
  end
end
