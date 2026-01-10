# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTPTest do
  use ExUnit.Case, async: true
  use Pleroma.Tests.Helpers

  import Tesla.Mock

  alias Pleroma.HTTP
  alias Pleroma.Utils.URIEncoding

  setup do
    mock(fn
      %{
        method: :get,
        url: "http://example.com/hello",
        headers: [{"content-type", "application/json"}]
      } ->
        json(%{"my" => "data"})

      %{method: :head, url: "http://example.com/hello"} ->
        %Tesla.Env{status: 200, body: ""}

      %{method: :get, url: "http://example.com/hello"} ->
        %Tesla.Env{status: 200, body: "hello"}

      %{method: :post, url: "http://example.com/world"} ->
        %Tesla.Env{status: 200, body: "world"}

      %{method: :get, url: "https://example.com/emoji/Pack%201/koronebless.png?foo=bar+baz"} ->
        %Tesla.Env{status: 200, body: "emoji data"}

      %{
        method: :get,
        url: "https://example.com/media/foo/bar%20!$&'()*+,;=/:%20@a%20%5Bbaz%5D.mp4"
      } ->
        %Tesla.Env{status: 200, body: "video data"}

      %{method: :get, url: "https://example.com/media/unicode%20%F0%9F%99%82%20.gif"} ->
        %Tesla.Env{status: 200, body: "unicode data"}

      %{
        method: :get,
        url:
          "https://i.guim.co.uk/img/media/1069ef13c447908272c4de94174cec2b6352cb2f/0_91_2000_1201/master/2000.jpg?width=1200&height=630&quality=85&auto=format&fit=crop&precrop=40:21,offset-x50,offset-y0&overlay-align=bottom%2Cleft&overlay-width=100p&overlay-base64=L2ltZy9zdGF0aWMvb3ZlcmxheXMvdGctb3BpbmlvbnMtYWdlLTIwMTkucG5n&enable=upscale&s=cba21427a73512fdc9863c486c03fdd8"
      } ->
        %Tesla.Env{status: 200, body: "Guardian image quirk"}

      %{
        method: :get,
        url:
          "https://i.guim.co.uk/emoji/Pack%201/koronebless.png?precrop=40:21,overlay-x0,overlay-y0&foo=bar+baz"
      } ->
        %Tesla.Env{status: 200, body: "Space in query with Guardian quirk"}

      %{
        method: :get,
        url:
          "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=accessKEY%2F20130721%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130721T201207Z&X-Amz-Expires=86400&X-Amz-Signature=SIGNATURE&X-Amz-SignedHeaders=host"
      } ->
        %Tesla.Env{status: 200, body: "AWS S3 data"}
    end)

    :ok
  end

  describe "head/1" do
    test "returns successfully result" do
      assert HTTP.head("http://example.com/hello") == {:ok, %Tesla.Env{status: 200, body: ""}}
    end
  end

  describe "get/1" do
    test "returns successfully result" do
      assert HTTP.get("http://example.com/hello") == {
               :ok,
               %Tesla.Env{status: 200, body: "hello"}
             }
    end
  end

  describe "get/2 (with headers)" do
    test "returns successfully result for json content-type" do
      assert HTTP.get("http://example.com/hello", [{"content-type", "application/json"}]) ==
               {
                 :ok,
                 %Tesla.Env{
                   status: 200,
                   body: "{\"my\":\"data\"}",
                   headers: [{"content-type", "application/json"}]
                 }
               }
    end
  end

  describe "post/2" do
    test "returns successfully result" do
      assert HTTP.post("http://example.com/world", "") == {
               :ok,
               %Tesla.Env{status: 200, body: "world"}
             }
    end
  end

  test "URL encoding properly encodes URLs with spaces" do
    clear_config(:test_url_encoding, true)

    url_with_space = "https://example.com/emoji/Pack 1/koronebless.png?foo=bar baz"

    {:ok, result} = HTTP.get(url_with_space)

    assert result.status == 200

    properly_encoded_url = "https://example.com/emoji/Pack%201/koronebless.png?foo=bar+baz"

    {:ok, result} = HTTP.get(properly_encoded_url)

    assert result.status == 200

    url_with_reserved_chars = "https://example.com/media/foo/bar !$&'()*+,;=/: @a [baz].mp4"

    {:ok, result} = HTTP.get(url_with_reserved_chars)

    assert result.status == 200

    url_with_unicode = "https://example.com/media/unicode 🙂 .gif"

    {:ok, result} = HTTP.get(url_with_unicode)

    assert result.status == 200
  end

  test "decodes URL first by default" do
    clear_config(:test_url_encoding, true)

    normal_url = "https://example.com/media/file%20with%20space.jpg?name=a+space.jpg"

    result = URIEncoding.encode_url(normal_url)

    assert result == "https://example.com/media/file%20with%20space.jpg?name=a+space.jpg"
  end

  test "doesn't decode URL first when specified" do
    clear_config(:test_url_encoding, true)

    normal_url = "https://example.com/media/file%20with%20space.jpg"

    result = URIEncoding.encode_url(normal_url, bypass_decode: true)

    assert result == "https://example.com/media/file%2520with%2520space.jpg"
  end

  test "properly applies Guardian image query quirk" do
    clear_config(:test_url_encoding, true)

    url =
      "https://i.guim.co.uk/img/media/1069ef13c447908272c4de94174cec2b6352cb2f/0_91_2000_1201/master/2000.jpg?width=1200&height=630&quality=85&auto=format&fit=crop&precrop=40:21,offset-x50,offset-y0&overlay-align=bottom%2Cleft&overlay-width=100p&overlay-base64=L2ltZy9zdGF0aWMvb3ZlcmxheXMvdGctb3BpbmlvbnMtYWdlLTIwMTkucG5n&enable=upscale&s=cba21427a73512fdc9863c486c03fdd8"

    result = URIEncoding.encode_url(url)

    assert result == url

    {:ok, result_get} = HTTP.get(result)

    assert result_get.status == 200
  end

  test "properly encodes spaces as \"pluses\" in query when using quirks" do
    clear_config(:test_url_encoding, true)

    url =
      "https://i.guim.co.uk/emoji/Pack 1/koronebless.png?precrop=40:21,overlay-x0,overlay-y0&foo=bar baz"

    properly_encoded_url =
      "https://i.guim.co.uk/emoji/Pack%201/koronebless.png?precrop=40:21,overlay-x0,overlay-y0&foo=bar+baz"

    result = URIEncoding.encode_url(url)

    assert result == properly_encoded_url

    {:ok, result_get} = HTTP.get(result)

    assert result_get.status == 200
  end

  test "properly encode AWS S3 queries" do
    clear_config(:test_url_encoding, true)

    url =
      "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=accessKEY%2F20130721%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130721T201207Z&X-Amz-Expires=86400&X-Amz-Signature=SIGNATURE&X-Amz-SignedHeaders=host"

    unencoded_url =
      "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=accessKEY/20130721/us-east-1/s3/aws4_request&X-Amz-Date=20130721T201207Z&X-Amz-Expires=86400&X-Amz-Signature=SIGNATURE&X-Amz-SignedHeaders=host"

    result = URIEncoding.encode_url(url)
    result_unencoded = URIEncoding.encode_url(unencoded_url)

    assert result == url
    assert result == result_unencoded

    {:ok, result_get} = HTTP.get(result)

    assert result_get.status == 200
  end

  test "preserves query key order" do
    clear_config(:test_url_encoding, true)

    url = "https://example.com/foo?hjkl=qwertz&xyz=abc&bar=baz"

    result = URIEncoding.encode_url(url)

    assert result == url
  end
end
