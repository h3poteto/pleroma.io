# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.WebFinger.WebFingerControllerTest do
  use Pleroma.Web.ConnCase

  import Pleroma.Factory
  import Tesla.Mock

  setup do
    mock(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  setup_all do: clear_config([:instance, :federating], true)

  test "GET host-meta" do
    response =
      build_conn()
      |> get("/.well-known/host-meta")

    assert response.status == 200

    response_xml =
      response.resp_body
      |> Floki.parse_document!(html_parser: Floki.HTMLParser.Mochiweb, attributes_as_maps: true)

    expected_xml =
      ~s(<?xml version="1.0" encoding="UTF-8"?><XRD xmlns="http://docs.oasis-open.org/ns/xri/xrd-1.0"><Link rel="lrdd" template="#{Pleroma.Web.Endpoint.url()}/.well-known/webfinger?resource={uri}" type="application/xrd+xml" /></XRD>)
      |> Floki.parse_document!(html_parser: Floki.HTMLParser.Mochiweb, attributes_as_maps: true)

    assert match?(^response_xml, expected_xml)
  end

  describe "Webfinger" do
    test "JRD" do
      clear_config([Pleroma.Web.Endpoint, :url, :host], "hyrule.world")
      clear_config([Pleroma.Web.WebFinger, :domain], "hyrule.world")

      user =
        insert(:user,
          ap_id: "https://hyrule.world/users/zelda"
        )

      response =
        build_conn()
        |> put_req_header("accept", "application/jrd+json")
        |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@hyrule.world")
        |> json_response(200)

      assert response["subject"] == "acct:#{user.nickname}@hyrule.world"

      assert response["aliases"] == [
               "https://hyrule.world/users/zelda"
             ]
    end

    test "XML" do
      clear_config([Pleroma.Web.Endpoint, :url, :host], "hyrule.world")
      clear_config([Pleroma.Web.WebFinger, :domain], "hyrule.world")

      user =
        insert(:user,
          ap_id: "https://hyrule.world/users/zelda"
        )

      response =
        build_conn()
        |> put_req_header("accept", "application/xrd+xml")
        |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@localhost")
        |> response(200)

      assert response =~ "<Alias>https://hyrule.world/users/zelda</Alias>"
    end
  end

  test "Webfinger defaults to JSON when no Accept header is provided" do
    clear_config([Pleroma.Web.Endpoint, :url, :host], "hyrule.world")
    clear_config([Pleroma.Web.WebFinger, :domain], "hyrule.world")

    user =
      insert(:user,
        ap_id: "https://hyrule.world/users/zelda"
      )

    response =
      build_conn()
      |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@hyrule.world")
      |> json_response(200)

    assert response["subject"] == "acct:#{user.nickname}@hyrule.world"

    assert response["aliases"] == [
             "https://hyrule.world/users/zelda"
           ]
  end

  describe "Webfinger returns also_known_as / aliases in the response" do
    test "JSON" do
      clear_config([Pleroma.Web.Endpoint, :url, :host], "hyrule.world")
      clear_config([Pleroma.Web.WebFinger, :domain], "hyrule.world")

      user =
        insert(:user,
          ap_id: "https://hyrule.world/users/zelda",
          also_known_as: [
            "https://mushroom.kingdom/users/toad",
            "https://luigi.mansion/users/kingboo"
          ]
        )

      response =
        build_conn()
        |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@hyrule.world")
        |> json_response(200)

      assert response["subject"] == "acct:#{user.nickname}@hyrule.world"

      assert response["aliases"] == [
               "https://hyrule.world/users/zelda",
               "https://mushroom.kingdom/users/toad",
               "https://luigi.mansion/users/kingboo"
             ]
    end

    test "XML" do
      clear_config([Pleroma.Web.Endpoint, :url, :host], "hyrule.world")
      clear_config([Pleroma.Web.WebFinger, :domain], "hyrule.world")

      user =
        insert(:user,
          ap_id: "https://hyrule.world/users/zelda",
          also_known_as: [
            "https://mushroom.kingdom/users/toad",
            "https://luigi.mansion/users/kingboo"
          ]
        )

      response =
        build_conn()
        |> put_req_header("accept", "application/xrd+xml")
        |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@localhost")
        |> response(200)

      assert response =~ "<Alias>https://hyrule.world/users/zelda</Alias>"
      assert response =~ "<Alias>https://mushroom.kingdom/users/toad</Alias>"
      assert response =~ "<Alias>https://luigi.mansion/users/kingboo</Alias>"
    end
  end

  test "reach user on tld, while pleroma is running on subdomain" do
    clear_config([Pleroma.Web.Endpoint, :url, :host], "sub.example.com")

    clear_config([Pleroma.Web.WebFinger, :domain], "example.com")

    user = insert(:user, ap_id: "https://sub.example.com/users/bobby", nickname: "bobby")

    response =
      build_conn()
      |> put_req_header("accept", "application/jrd+json")
      |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@example.com")
      |> json_response(200)

    assert response["subject"] == "acct:#{user.nickname}@example.com"
    assert response["aliases"] == ["https://sub.example.com/users/#{user.nickname}"]
  end

  describe "it returns 404 when user isn't found" do
    test "JSON" do
      result =
        build_conn()
        |> put_req_header("accept", "application/jrd+json")
        |> get("/.well-known/webfinger?resource=acct:jimm@localhost")
        |> json_response(404)

      assert result == "Couldn't find user"
    end

    test "XML" do
      result =
        build_conn()
        |> put_req_header("accept", "application/xrd+xml")
        |> get("/.well-known/webfinger?resource=acct:jimm@localhost")
        |> response(404)

      assert result == "Couldn't find user"
    end
  end

  test "Returns JSON when format is not supported" do
    clear_config([Pleroma.Web.Endpoint, :url, :host], "hyrule.world")
    clear_config([Pleroma.Web.WebFinger, :domain], "hyrule.world")

    user =
      insert(:user,
        ap_id: "https://hyrule.world/users/zelda",
        also_known_as: ["https://mushroom.kingdom/users/toad"]
      )

    response =
      build_conn()
      |> put_req_header("accept", "text/html")
      |> get("/.well-known/webfinger?resource=acct:#{user.nickname}@hyrule.world")
      |> json_response(200)

    assert response["subject"] == "acct:#{user.nickname}@hyrule.world"

    assert response["aliases"] == [
             "https://hyrule.world/users/zelda",
             "https://mushroom.kingdom/users/toad"
           ]
  end

  test "Sends a 400 when resource param is missing" do
    response =
      build_conn()
      |> put_req_header("accept", "application/xrd+xml,application/jrd+json")
      |> get("/.well-known/webfinger")

    assert response(response, 400)
  end
end
