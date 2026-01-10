# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MediaProxyTest do
  use ExUnit.Case
  use Pleroma.Tests.Helpers

  alias Pleroma.Config
  alias Pleroma.UnstubbedConfigMock, as: ConfigMock
  alias Pleroma.Web.Endpoint
  alias Pleroma.Web.MediaProxy

  import Mox

  setup do
    ConfigMock
    |> stub_with(Pleroma.Test.StaticConfig)

    :ok
  end

  defp decode_result(encoded) do
    {:ok, decoded} = MediaProxy.decode_url(encoded)
    decoded
  end

  describe "when enabled" do
    setup do: clear_config([:media_proxy, :enabled], true)

    test "ignores invalid url" do
      assert MediaProxy.url(nil) == nil
      assert MediaProxy.url("") == nil
    end

    test "ignores relative url" do
      assert MediaProxy.url("/local") == "/local"
      assert MediaProxy.url("/") == "/"
    end

    test "ignores local url" do
      local_url = Endpoint.url() <> "/hello"
      local_root = Endpoint.url()
      assert MediaProxy.url(local_url) == local_url
      assert MediaProxy.url(local_root) == local_root
    end

    test "encodes and decodes URL" do
      url = "https://pleroma.soykaf.com/static/logo.png"
      encoded = MediaProxy.url(url)

      assert String.starts_with?(
               encoded,
               Config.get([:media_proxy, :base_url], Pleroma.Web.Endpoint.url())
             )

      assert String.ends_with?(encoded, "/logo.png")

      assert decode_result(encoded) == url
    end

    test "encodes and decodes URL without a path" do
      url = "https://pleroma.soykaf.com"
      encoded = MediaProxy.url(url)
      assert decode_result(encoded) == url
    end

    test "encodes and decodes URL without an extension" do
      url = "https://pleroma.soykaf.com/path/"
      encoded = MediaProxy.url(url)
      assert String.ends_with?(encoded, "/path")
      assert decode_result(encoded) == url
    end

    test "encodes and decodes URL and ignores query params for the path" do
      url = "https://pleroma.soykaf.com/static/logo.png?93939393939=&bunny=true"
      encoded = MediaProxy.url(url)
      assert String.ends_with?(encoded, "/logo.png")
      assert decode_result(encoded) == url
    end

    test "validates signature" do
      encoded = MediaProxy.url("https://pleroma.social")

      clear_config(
        [Endpoint, :secret_key_base],
        "00000000000000000000000000000000000000000000000"
      )

      [_, "proxy", sig, base64 | _] = URI.parse(encoded).path |> String.split("/")
      assert MediaProxy.decode_url(sig, base64) == {:error, :invalid_signature}
    end

    def test_verify_request_path_and_url(request_path, url, expected_result) do
      assert MediaProxy.verify_request_path_and_url(request_path, url) == expected_result

      assert MediaProxy.verify_request_path_and_url(
               %Plug.Conn{
                 params: %{"filename" => Path.basename(request_path)},
                 request_path: request_path
               },
               url
             ) == expected_result
    end

    test "if first arg of `verify_request_path_and_url/2` is a Plug.Conn without \"filename\" " <>
           "parameter, `verify_request_path_and_url/2` returns :ok " do
      assert MediaProxy.verify_request_path_and_url(
               %Plug.Conn{params: %{}, request_path: "/some/path"},
               "https://instance.com/file.jpg"
             ) == :ok

      assert MediaProxy.verify_request_path_and_url(
               %Plug.Conn{params: %{}, request_path: "/path/to/file.jpg"},
               "https://instance.com/file.jpg"
             ) == :ok
    end

    test "`verify_request_path_and_url/2` preserves the encoded or decoded path" do
      test_verify_request_path_and_url(
        "/Hello world.jpg",
        "http://pleroma.social/Hello world.jpg",
        :ok
      )

      test_verify_request_path_and_url(
        "/Hello%20world.jpg",
        "http://pleroma.social/Hello%20world.jpg",
        :ok
      )

      test_verify_request_path_and_url(
        "/my%2Flong%2Furl%2F2019%2F07%2FS.jpg",
        "http://pleroma.social/my%2Flong%2Furl%2F2019%2F07%2FS.jpg",
        :ok
      )

      test_verify_request_path_and_url(
        # Note: `conn.request_path` returns encoded url
        "/ANALYSE-DAI-_-LE-STABLECOIN-100-D%C3%89CENTRALIS%C3%89-BQ.jpg",
        "https://mydomain.com/uploads/2019/07/ANALYSE-DAI-_-LE-STABLECOIN-100-DÉCENTRALISÉ-BQ.jpg",
        :ok
      )

      test_verify_request_path_and_url(
        "/my%2Flong%2Furl%2F2019%2F07%2FS",
        "http://pleroma.social/my%2Flong%2Furl%2F2019%2F07%2FS.jpg",
        {:wrong_filename, "my%2Flong%2Furl%2F2019%2F07%2FS.jpg"}
      )
    end

    test "uses the configured base_url" do
      base_url = "https://cache.pleroma.social"
      clear_config([:media_proxy, :base_url], base_url)

      url = "https://pleroma.soykaf.com/static/logo.png"
      encoded = MediaProxy.url(url)

      assert String.starts_with?(encoded, base_url)
    end

    # This includes unsafe/reserved characters which are not interpreted as part of the URL
    # and would otherwise have to be ASCII encoded. It is our role to ensure the proxied URL
    # is unmodified, so we are testing these characters anyway.
    test "preserve non-unicode characters per RFC3986" do
      url =
        "https://pleroma.com/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890-._~:/?#[]@!$&'()*+,;=|^`{}"

      encoded = MediaProxy.url(url)
      assert decode_result(encoded) == url
    end

    # Improperly encoded URLs should not happen even when input was wrong.
    test "does not preserve unicode characters" do
      url = "https://ko.wikipedia.org/wiki/위키백과:대문"

      encoded_url =
        "https://ko.wikipedia.org/wiki/%EC%9C%84%ED%82%A4%EB%B0%B1%EA%B3%BC:%EB%8C%80%EB%AC%B8"

      encoded = MediaProxy.url(url)
      assert decode_result(encoded) == encoded_url
    end

    # If we preserve wrongly encoded URLs in MediaProxy, it will get fixed
    # when we GET these URLs and will result in 424 when MediaProxy previews are enabled.
    test "does not preserve incorrect URLs when making MediaProxy link" do
      incorrect_original_url = "https://example.com/media/cofe%20%28with%20milk%29.png"
      corrected_original_url = "https://example.com/media/cofe%20(with%20milk).png"

      unpreserved_encoded_original_url =
        "http://localhost:4001/proxy/Sv6tt6xjA72_i4d8gXbuMAOXQSs/aHR0cHM6Ly9leGFtcGxlLmNvbS9tZWRpYS9jb2ZlJTIwKHdpdGglMjBtaWxrKS5wbmc/cofe%20(with%20milk).png"

      encoded = MediaProxy.url(incorrect_original_url)

      assert encoded == unpreserved_encoded_original_url
      assert decode_result(encoded) == corrected_original_url
    end
  end

  describe "when disabled" do
    setup do: clear_config([:media_proxy, :enabled], false)

    test "does not encode remote urls" do
      assert MediaProxy.url("https://google.fr") == "https://google.fr"
    end
  end

  describe "whitelist" do
    setup do: clear_config([:media_proxy, :enabled], true)

    test "mediaproxy whitelist" do
      clear_config([:media_proxy, :whitelist], ["https://google.com", "https://feld.me"])
      url = "https://feld.me/foo.png"

      unencoded = MediaProxy.url(url)
      assert unencoded == url
    end

    # TODO: delete after removing support bare domains for media proxy whitelist
    test "mediaproxy whitelist bare domains whitelist (deprecated)" do
      clear_config([:media_proxy, :whitelist], ["google.com", "feld.me"])
      url = "https://feld.me/foo.png"

      unencoded = MediaProxy.url(url)
      assert unencoded == url
    end

    test "does not change whitelisted urls" do
      clear_config([:media_proxy, :whitelist], ["mycdn.akamai.com"])
      clear_config([:media_proxy, :base_url], "https://cache.pleroma.social")

      media_url = "https://mycdn.akamai.com"

      url = "#{media_url}/static/logo.png"
      encoded = MediaProxy.url(url)

      assert String.starts_with?(encoded, media_url)
    end

    test "ensure Pleroma.Upload base_url is always whitelisted" do
      media_url = "https://media.pleroma.social"

      ConfigMock
      |> stub(:get, fn
        [Pleroma.Upload, :base_url] -> media_url
        path -> Pleroma.Test.StaticConfig.get(path)
      end)

      url = "#{media_url}/static/logo.png"
      encoded = MediaProxy.url(url)

      assert String.starts_with?(encoded, media_url)
    end
  end
end
