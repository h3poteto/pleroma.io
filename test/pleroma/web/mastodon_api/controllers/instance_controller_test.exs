# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.InstanceControllerTest do
  # TODO: Should not need Cachex
  use Pleroma.Web.ConnCase

  alias Pleroma.Rule
  alias Pleroma.User
  import Pleroma.Factory

  test "get instance information", %{conn: conn} do
    conn = get(conn, "/api/v1/instance")
    assert result = json_response_and_validate_schema(conn, 200)

    email = Pleroma.Config.get([:instance, :email])
    thumbnail = Pleroma.Web.Endpoint.url() <> Pleroma.Config.get([:instance, :instance_thumbnail])
    background = Pleroma.Web.Endpoint.url() <> Pleroma.Config.get([:instance, :background_image])

    # Note: not checking for "max_toot_chars" since it's optional
    assert %{
             "uri" => _,
             "title" => _,
             "description" => _,
             "short_description" => _,
             "version" => _,
             "email" => from_config_email,
             "urls" => %{
               "streaming_api" => _
             },
             "stats" => _,
             "thumbnail" => from_config_thumbnail,
             "languages" => _,
             "registrations" => _,
             "approval_required" => _,
             "poll_limits" => _,
             "upload_limit" => _,
             "avatar_upload_limit" => _,
             "background_upload_limit" => _,
             "banner_upload_limit" => _,
             "background_image" => from_config_background,
             "shout_limit" => _,
             "description_limit" => _,
             "rules" => _
           } = result

    assert result["pleroma"]["metadata"]["account_activation_required"] != nil
    assert result["pleroma"]["metadata"]["features"]
    assert result["pleroma"]["metadata"]["federation"]
    assert result["pleroma"]["metadata"]["fields_limits"]
    assert result["pleroma"]["vapid_public_key"]
    assert result["pleroma"]["stats"]["mau"] == 0

    assert email == from_config_email
    assert thumbnail == from_config_thumbnail
    assert background == from_config_background
  end

  test "get instance stats", %{conn: conn} do
    user = insert(:user, %{local: true})

    user2 = insert(:user, %{local: true})
    {:ok, _user2} = User.set_activation(user2, false)

    insert(:user, %{local: false, nickname: "u@peer1.com"})
    insert(:user, %{local: false, nickname: "u@peer2.com"})

    {:ok, _} = Pleroma.Web.CommonAPI.post(user, %{status: "cofe"})

    Pleroma.Stats.force_update()

    conn = get(conn, "/api/v1/instance")

    assert result = json_response_and_validate_schema(conn, 200)

    stats = result["stats"]

    assert stats
    assert stats["user_count"] == 1
    assert stats["status_count"] == 1
    assert stats["domain_count"] == 2
  end

  test "get peers", %{conn: conn} do
    insert(:user, %{local: false, nickname: "u@peer1.com"})
    insert(:user, %{local: false, nickname: "u@peer2.com"})

    Pleroma.Stats.force_update()

    conn = get(conn, "/api/v1/instance/peers")

    assert result = json_response_and_validate_schema(conn, 200)

    assert ["peer1.com", "peer2.com"] == Enum.sort(result)
  end

  test "instance languages", %{conn: conn} do
    assert %{"languages" => ["en"]} =
             conn
             |> get("/api/v1/instance")
             |> json_response_and_validate_schema(200)

    clear_config([:instance, :languages], ["aa", "bb"])

    assert %{"languages" => ["aa", "bb"]} =
             conn
             |> get("/api/v1/instance")
             |> json_response_and_validate_schema(200)
  end

  test "get instance contact information", %{conn: conn} do
    user = insert(:user, %{local: true})

    clear_config([:instance, :contact_username], user.nickname)

    conn = get(conn, "/api/v1/instance")

    assert result = json_response_and_validate_schema(conn, 200)

    assert result["contact_account"]["id"] == user.id
  end

  test "get instance information v2", %{conn: conn} do
    clear_config([:auth, :oauth_consumer_strategies], [])

    assert get(conn, "/api/v2/instance")
           |> json_response_and_validate_schema(200)
  end

  test "get instance rules", %{conn: conn} do
    Rule.create(%{text: "Example rule", hint: "Rule description", priority: 1})
    Rule.create(%{text: "Third rule", priority: 2})
    Rule.create(%{text: "Second rule", priority: 1})

    conn = get(conn, "/api/v1/instance")

    assert result = json_response_and_validate_schema(conn, 200)

    assert [
             %{
               "text" => "Example rule",
               "hint" => "Rule description"
             },
             %{
               "text" => "Second rule",
               "hint" => ""
             },
             %{
               "text" => "Third rule",
               "hint" => ""
             }
           ] = result["rules"]
  end

  test "translation languages matrix", %{conn: conn} do
    clear_config([Pleroma.Language.Translation, :provider], TranslationMock)

    assert %{"en" => ["pl"], "pl" => ["en"]} =
             conn
             |> get("/api/v1/instance/translation_languages")
             |> json_response_and_validate_schema(200)
  end

  test "base_urls in pleroma metadata", %{conn: conn} do
    media_proxy_base_url = "https://media.example.org"
    upload_base_url = "https://uploads.example.org"

    clear_config([:media_proxy, :enabled], true)
    clear_config([:media_proxy, :base_url], media_proxy_base_url)
    clear_config([Pleroma.Upload, :base_url], upload_base_url)

    conn = get(conn, "/api/v1/instance")

    assert result = json_response_and_validate_schema(conn, 200)
    assert result["pleroma"]["metadata"]["base_urls"]["media_proxy"] == media_proxy_base_url
    assert result["pleroma"]["metadata"]["base_urls"]["upload"] == upload_base_url

    # Test when media_proxy is disabled
    clear_config([:media_proxy, :enabled], false)

    conn = get(conn, "/api/v1/instance")

    assert result = json_response_and_validate_schema(conn, 200)
    refute Map.has_key?(result["pleroma"]["metadata"]["base_urls"], "media_proxy")
    assert result["pleroma"]["metadata"]["base_urls"]["upload"] == upload_base_url

    # Test when upload base_url is not set
    clear_config([Pleroma.Upload, :base_url], nil)

    conn = get(conn, "/api/v1/instance")

    assert result = json_response_and_validate_schema(conn, 200)
    refute Map.has_key?(result["pleroma"]["metadata"]["base_urls"], "media_proxy")
    refute Map.has_key?(result["pleroma"]["metadata"]["base_urls"], "upload")
  end

  test "display timeline access restrictions", %{conn: conn} do
    clear_config([:restrict_unauthenticated, :timelines, :local], true)
    clear_config([:restrict_unauthenticated, :timelines, :federated], false)

    conn = get(conn, "/api/v2/instance")

    assert result = json_response_and_validate_schema(conn, 200)

    assert result["configuration"]["timelines_access"] == %{
             "live_feeds" => %{
               "local" => "authenticated",
               "remote" => "public"
             },
             "hashtag_feeds" => %{
               "local" => "authenticated",
               "remote" => "public"
             },
             "trending_link_feeds" => %{
               "local" => "disabled",
               "remote" => "disabled"
             }
           }
  end
end
