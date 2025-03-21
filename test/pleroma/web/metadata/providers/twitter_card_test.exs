# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Metadata.Providers.TwitterCardTest do
  use Pleroma.DataCase
  import Pleroma.Factory

  alias Pleroma.User
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.Endpoint
  alias Pleroma.Web.MediaProxy
  alias Pleroma.Web.Metadata.Providers.TwitterCard
  alias Pleroma.Web.Metadata.Utils
  alias Pleroma.Web.Router

  setup do: clear_config([Pleroma.Web.Metadata, :unfurl_nsfw])

  test "it renders twitter card for user info" do
    user = insert(:user, name: "Jimmy Hendriks", bio: "born 19 March 1994")
    avatar_url = MediaProxy.preview_url(User.avatar_url(user))
    res = TwitterCard.build_tags(%{user: user})

    assert res == [
             {:meta, [name: "twitter:title", content: Utils.user_name_string(user)], []},
             {:meta, [name: "twitter:description", content: "born 19 March 1994"], []},
             {:meta, [name: "twitter:image", content: avatar_url], []},
             {:meta, [name: "twitter:card", content: "summary"], []}
           ]
  end

  test "it uses summary twittercard if post has no attachment" do
    user = insert(:user, name: "Jimmy Hendriks", bio: "born 19 March 1994")
    {:ok, activity} = CommonAPI.post(user, %{status: "HI"})

    note =
      insert(:note, %{
        data: %{
          "actor" => user.ap_id,
          "tag" => [],
          "id" => "https://pleroma.gov/objects/whatever",
          "summary" => "",
          "content" => "pleroma in a nutshell"
        }
      })

    result = TwitterCard.build_tags(%{object: note, user: user, activity_id: activity.id})

    assert [
             {:meta, [name: "twitter:title", content: Utils.user_name_string(user)], []},
             {:meta, [name: "twitter:description", content: "pleroma in a nutshell"], []},
             {:meta, [name: "twitter:image", content: "http://localhost:4001/images/avi.png"],
              []},
             {:meta, [name: "twitter:card", content: "summary"], []}
           ] == result
  end

  test "it uses summary as description if post has one" do
    user = insert(:user, name: "Jimmy Hendriks", bio: "born 19 March 1994")
    {:ok, activity} = CommonAPI.post(user, %{status: "HI"})

    note =
      insert(:note, %{
        data: %{
          "actor" => user.ap_id,
          "tag" => [],
          "id" => "https://pleroma.gov/objects/whatever",
          "summary" => "Public service announcement on caffeine consumption",
          "content" => "cofe"
        }
      })

    result = TwitterCard.build_tags(%{object: note, user: user, activity_id: activity.id})

    assert [
             {:meta, [name: "twitter:title", content: Utils.user_name_string(user)], []},
             {:meta,
              [
                name: "twitter:description",
                content: "Public service announcement on caffeine consumption"
              ], []},
             {:meta, [name: "twitter:image", content: "http://localhost:4001/images/avi.png"],
              []},
             {:meta, [name: "twitter:card", content: "summary"], []}
           ] == result
  end

  test "it renders avatar not attachment if post is nsfw and unfurl_nsfw is disabled" do
    clear_config([Pleroma.Web.Metadata, :unfurl_nsfw], false)
    user = insert(:user, name: "Jimmy Hendriks", bio: "born 19 March 1994")
    {:ok, activity} = CommonAPI.post(user, %{status: "HI"})

    note =
      insert(:note, %{
        data: %{
          "actor" => user.ap_id,
          "tag" => [],
          "id" => "https://pleroma.gov/objects/whatever",
          "summary" => "",
          "content" => "pleroma in a nutshell",
          "sensitive" => true,
          "attachment" => [
            %{
              "url" => [%{"mediaType" => "image/png", "href" => "https://pleroma.gov/tenshi.png"}]
            },
            %{
              "url" => [
                %{
                  "mediaType" => "application/octet-stream",
                  "href" => "https://pleroma.gov/fqa/badapple.sfc"
                }
              ]
            },
            %{
              "url" => [
                %{"mediaType" => "video/webm", "href" => "https://pleroma.gov/about/juche.webm"}
              ]
            }
          ]
        }
      })

    result = TwitterCard.build_tags(%{object: note, user: user, activity_id: activity.id})

    assert [
             {:meta, [name: "twitter:title", content: Utils.user_name_string(user)], []},
             {:meta, [name: "twitter:description", content: "pleroma in a nutshell"], []},
             {:meta, [name: "twitter:image", content: "http://localhost:4001/images/avi.png"],
              []},
             {:meta, [name: "twitter:card", content: "summary"], []}
           ] == result
  end

  test "it renders supported types of attachments and skips unknown types" do
    user = insert(:user, name: "Jimmy Hendriks", bio: "born 19 March 1994")
    {:ok, activity} = CommonAPI.post(user, %{status: "HI"})

    note =
      insert(:note, %{
        data: %{
          "actor" => user.ap_id,
          "tag" => [],
          "id" => "https://pleroma.gov/objects/whatever",
          "summary" => "",
          "content" => "pleroma in a nutshell",
          "attachment" => [
            %{
              "url" => [
                %{
                  "mediaType" => "image/png",
                  "href" => "https://pleroma.gov/tenshi.png",
                  "height" => 1024,
                  "width" => 1280
                }
              ]
            },
            %{
              "url" => [
                %{
                  "mediaType" => "application/octet-stream",
                  "href" => "https://pleroma.gov/fqa/badapple.sfc"
                }
              ]
            },
            %{
              "url" => [
                %{
                  "mediaType" => "video/webm",
                  "href" => "https://pleroma.gov/about/juche.webm",
                  "height" => 600,
                  "width" => 800
                }
              ]
            }
          ]
        }
      })

    result = TwitterCard.build_tags(%{object: note, user: user, activity_id: activity.id})

    assert [
             {:meta, [name: "twitter:title", content: Utils.user_name_string(user)], []},
             {:meta, [name: "twitter:description", content: "pleroma in a nutshell"], []},
             {:meta, [name: "twitter:card", content: "summary_large_image"], []},
             {:meta, [name: "twitter:image", content: "https://pleroma.gov/tenshi.png"], []},
             {:meta, [name: "twitter:image:alt", content: ""], []},
             {:meta, [name: "twitter:player:width", content: "1280"], []},
             {:meta, [name: "twitter:player:height", content: "1024"], []},
             {:meta, [name: "twitter:card", content: "player"], []},
             {:meta,
              [
                name: "twitter:player",
                content: Router.Helpers.o_status_url(Endpoint, :notice_player, activity.id)
              ], []},
             {:meta, [name: "twitter:player:width", content: "800"], []},
             {:meta, [name: "twitter:player:height", content: "600"], []},
             {:meta,
              [
                name: "twitter:player:stream",
                content: "https://pleroma.gov/about/juche.webm"
              ], []},
             {:meta, [name: "twitter:player:stream:content_type", content: "video/webm"], []}
           ] == result
  end

  test "meta tag ordering matches attachment order" do
    user = insert(:user, name: "Jimmy Hendriks", bio: "born 19 March 1994")

    note =
      insert(:note, %{
        data: %{
          "actor" => user.ap_id,
          "tag" => [],
          "id" => "https://pleroma.gov/objects/whatever",
          "summary" => "",
          "content" => "pleroma in a nutshell",
          "attachment" => [
            %{
              "url" => [
                %{
                  "mediaType" => "image/png",
                  "href" => "https://example.com/first.png",
                  "height" => 1024,
                  "width" => 1280
                }
              ]
            },
            %{
              "url" => [
                %{
                  "mediaType" => "image/png",
                  "href" => "https://example.com/second.png",
                  "height" => 1024,
                  "width" => 1280
                }
              ]
            }
          ]
        }
      })

    result = TwitterCard.build_tags(%{object: note, activity_id: note.data["id"], user: user})

    assert [
             {:meta, [name: "twitter:title", content: Utils.user_name_string(user)], []},
             {:meta, [name: "twitter:description", content: "pleroma in a nutshell"], []},
             {:meta, [name: "twitter:card", content: "summary_large_image"], []},
             {:meta, [name: "twitter:image", content: "https://example.com/first.png"], []},
             {:meta, [name: "twitter:image:alt", content: ""], []},
             {:meta, [name: "twitter:player:width", content: "1280"], []},
             {:meta, [name: "twitter:player:height", content: "1024"], []},
             {:meta, [name: "twitter:card", content: "summary_large_image"], []},
             {:meta, [name: "twitter:image", content: "https://example.com/second.png"], []},
             {:meta, [name: "twitter:image:alt", content: ""], []},
             {:meta, [name: "twitter:player:width", content: "1280"], []},
             {:meta, [name: "twitter:player:height", content: "1024"], []}
           ] == result
  end
end
