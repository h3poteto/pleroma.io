# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.ReverseProxyTest do
  use Pleroma.Web.ConnCase
  import ExUnit.CaptureLog
  import Mox

  alias Pleroma.ReverseProxy
  alias Pleroma.ReverseProxy.ClientMock
  alias Plug.Conn

  setup_all do
    {:ok, _} = Registry.start_link(keys: :unique, name: ClientMock)
    :ok
  end

  setup :verify_on_exit!

  defp request_mock(invokes) do
    ClientMock
    |> expect(:request, fn :get, url, headers, _body, _opts ->
      Registry.register(ClientMock, url, 0)
      body = headers |> Enum.into(%{}) |> Jason.encode!()

      {:ok, 200,
       [
         {"content-type", "application/json"},
         {"content-length", byte_size(body) |> to_string()}
       ], %{url: url, body: body}}
    end)
    |> expect(:stream_body, invokes, fn %{url: url, body: body} = client ->
      case Registry.lookup(ClientMock, url) do
        [{_, 0}] ->
          Registry.update_value(ClientMock, url, &(&1 + 1))
          {:ok, body, client}

        [{_, 1}] ->
          Registry.unregister(ClientMock, url)
          :done
      end
    end)
  end

  describe "reverse proxy" do
    test "do not track successful request", %{conn: conn} do
      request_mock(2)
      url = "/success"

      conn = ReverseProxy.call(conn, url)

      assert conn.status == 200
      assert Cachex.get(:failed_proxy_url_cache, url) == {:ok, nil}
    end
  end

  test "use Pleroma's user agent in the request; don't pass the client's", %{conn: conn} do
    request_mock(2)

    conn =
      conn
      |> Plug.Conn.put_req_header("user-agent", "fake/1.0")
      |> ReverseProxy.call("/user-agent")

    # Convert the response to a map without relying on json_response
    body = conn.resp_body
    assert conn.status == 200
    response = Jason.decode!(body)
    assert response == %{"user-agent" => Pleroma.Application.user_agent()}
  end

  test "closed connection", %{conn: conn} do
    ClientMock
    |> expect(:request, fn :get, "/closed", _, _, _ -> {:ok, 200, [], %{}} end)
    |> expect(:stream_body, fn _ -> {:error, :closed} end)
    |> expect(:close, fn _ -> :ok end)

    conn = ReverseProxy.call(conn, "/closed")
    assert conn.halted
  end

  defp stream_mock(invokes, with_close? \\ false) do
    ClientMock
    |> expect(:request, fn :get, "/stream-bytes/" <> length, _, _, _ ->
      Registry.register(ClientMock, "/stream-bytes/" <> length, 0)

      {:ok, 200, [{"content-type", "application/octet-stream"}],
       %{url: "/stream-bytes/" <> length}}
    end)
    |> expect(:stream_body, invokes, fn %{url: "/stream-bytes/" <> length} = client ->
      max = String.to_integer(length)

      case Registry.lookup(ClientMock, "/stream-bytes/" <> length) do
        [{_, current}] when current < max ->
          Registry.update_value(
            ClientMock,
            "/stream-bytes/" <> length,
            &(&1 + 10)
          )

          {:ok, "0123456789", client}

        [{_, ^max}] ->
          Registry.unregister(ClientMock, "/stream-bytes/" <> length)
          :done
      end
    end)

    if with_close? do
      expect(ClientMock, :close, fn _ -> :ok end)
    end
  end

  describe "max_body" do
    test "length returns error if content-length more than option", %{conn: conn} do
      request_mock(0)

      assert capture_log(fn ->
               ReverseProxy.call(conn, "/huge-file", max_body_length: 4)
             end) =~
               "[error] Elixir.Pleroma.ReverseProxy: request to \"/huge-file\" failed: :body_too_large"

      assert {:ok, true} == Cachex.get(:failed_proxy_url_cache, "/huge-file")

      assert capture_log(fn ->
               ReverseProxy.call(conn, "/huge-file", max_body_length: 4)
             end) == ""
    end

    test "max_body_length returns error if streaming body more than that option", %{conn: conn} do
      stream_mock(3, true)

      assert capture_log(fn ->
               ReverseProxy.call(conn, "/stream-bytes/50", max_body_length: 30)
             end) =~
               "Elixir.Pleroma.ReverseProxy request to /stream-bytes/50 failed while reading/chunking: :body_too_large"
    end
  end

  describe "HEAD requests" do
    test "common", %{conn: conn} do
      ClientMock
      |> expect(:request, fn :head, "/head", _, _, _ ->
        {:ok, 200, [{"content-type", "image/png"}]}
      end)

      conn = ReverseProxy.call(Map.put(conn, :method, "HEAD"), "/head")

      assert conn.status == 200
      assert Conn.get_resp_header(conn, "content-type") == ["image/png"]
      assert conn.resp_body == ""
    end
  end

  defp error_mock(status) when is_integer(status) do
    ClientMock
    |> expect(:request, fn :get, "/status/" <> _, _, _, _ ->
      {:error, status}
    end)
  end

  describe "returns error on" do
    test "500", %{conn: conn} do
      error_mock(500)
      url = "/status/500"

      capture_log(fn -> ReverseProxy.call(conn, url) end) =~
        "[error] Elixir.Pleroma.ReverseProxy: request to /status/500 failed with HTTP status 500"

      assert Cachex.get(:failed_proxy_url_cache, url) == {:ok, true}

      {:ok, ttl} = Cachex.ttl(:failed_proxy_url_cache, url)
      assert ttl <= 60_000
    end

    test "400", %{conn: conn} do
      error_mock(400)
      url = "/status/400"

      capture_log(fn -> ReverseProxy.call(conn, url) end) =~
        "[error] Elixir.Pleroma.ReverseProxy: request to /status/400 failed with HTTP status 400"

      assert Cachex.get(:failed_proxy_url_cache, url) == {:ok, true}
      assert Cachex.ttl(:failed_proxy_url_cache, url) == {:ok, nil}
    end

    test "403", %{conn: conn} do
      error_mock(403)
      url = "/status/403"

      capture_log(fn ->
        ReverseProxy.call(conn, url, failed_request_ttl: :timer.seconds(120))
      end) =~
        "[error] Elixir.Pleroma.ReverseProxy: request to /status/403 failed with HTTP status 403"

      {:ok, ttl} = Cachex.ttl(:failed_proxy_url_cache, url)
      assert ttl > 100_000
    end

    test "204", %{conn: conn} do
      url = "/status/204"
      expect(ClientMock, :request, fn :get, _url, _, _, _ -> {:ok, 204, [], %{}} end)

      capture_log(fn ->
        conn = ReverseProxy.call(conn, url)
        assert conn.resp_body == "Request failed: No Content"
        assert conn.halted
      end) =~
        "[error] Elixir.Pleroma.ReverseProxy: request to \"/status/204\" failed with HTTP status 204"

      assert Cachex.get(:failed_proxy_url_cache, url) == {:ok, true}
      assert Cachex.ttl(:failed_proxy_url_cache, url) == {:ok, nil}
    end
  end

  test "streaming", %{conn: conn} do
    stream_mock(21)
    conn = ReverseProxy.call(conn, "/stream-bytes/200")
    assert conn.state == :chunked
    assert byte_size(conn.resp_body) == 200
    assert Conn.get_resp_header(conn, "content-type") == ["application/octet-stream"]
  end

  defp headers_mock(_) do
    ClientMock
    |> expect(:request, fn :get, "/headers", headers, _, _ ->
      Registry.register(ClientMock, "/headers", 0)
      {:ok, 200, [{"content-type", "application/json"}], %{url: "/headers", headers: headers}}
    end)
    |> expect(:stream_body, 2, fn %{url: url, headers: headers} = client ->
      case Registry.lookup(ClientMock, url) do
        [{_, 0}] ->
          Registry.update_value(ClientMock, url, &(&1 + 1))
          headers = for {k, v} <- headers, into: %{}, do: {String.capitalize(k), v}
          {:ok, Jason.encode!(%{headers: headers}), client}

        [{_, 1}] ->
          Registry.unregister(ClientMock, url)
          :done
      end
    end)

    :ok
  end

  describe "keep request headers" do
    setup [:headers_mock]

    test "header passes", %{conn: conn} do
      conn =
        Conn.put_req_header(
          conn,
          "accept",
          "text/html"
        )
        |> ReverseProxy.call("/headers")

      body = conn.resp_body
      assert conn.status == 200
      response = Jason.decode!(body)
      headers = response["headers"]
      assert headers["Accept"] == "text/html"
    end

    test "header is filtered", %{conn: conn} do
      conn =
        Conn.put_req_header(
          conn,
          "accept-language",
          "en-US"
        )
        |> ReverseProxy.call("/headers")

      body = conn.resp_body
      assert conn.status == 200
      response = Jason.decode!(body)
      headers = response["headers"]
      refute headers["Accept-Language"]
    end
  end

  test "returns 400 on non GET, HEAD requests", %{conn: conn} do
    conn = ReverseProxy.call(Map.put(conn, :method, "POST"), "/ip")
    assert conn.status == 400
  end

  describe "cache resp headers" do
    test "add cache-control", %{conn: conn} do
      ClientMock
      |> expect(:request, fn :get, "/cache", _, _, _ ->
        {:ok, 200, [{"ETag", "some ETag"}], %{}}
      end)
      |> expect(:stream_body, fn _ -> :done end)

      conn = ReverseProxy.call(conn, "/cache")
      assert {"cache-control", "public, max-age=1209600"} in conn.resp_headers
    end
  end

  defp disposition_headers_mock(headers) do
    ClientMock
    |> expect(:request, fn :get, "/disposition", _, _, _ ->
      Registry.register(ClientMock, "/disposition", 0)

      {:ok, 200, headers, %{url: "/disposition"}}
    end)
    |> expect(:stream_body, 2, fn %{url: "/disposition"} = client ->
      case Registry.lookup(ClientMock, "/disposition") do
        [{_, 0}] ->
          Registry.update_value(ClientMock, "/disposition", &(&1 + 1))
          {:ok, "", client}

        [{_, 1}] ->
          Registry.unregister(ClientMock, "/disposition")
          :done
      end
    end)
  end

  describe "response content disposition header" do
    test "not attachment", %{conn: conn} do
      disposition_headers_mock([
        {"content-type", "image/gif"},
        {"content-length", "0"}
      ])

      conn = ReverseProxy.call(conn, "/disposition")

      assert {"content-type", "image/gif"} in conn.resp_headers
    end

    test "with content-disposition header", %{conn: conn} do
      disposition_headers_mock([
        {"content-disposition", "attachment; filename=\"filename.jpg\""},
        {"content-length", "0"}
      ])

      conn = ReverseProxy.call(conn, "/disposition")

      assert {"content-disposition", "attachment; filename=\"filename.jpg\""} in conn.resp_headers
    end
  end

  describe "content-type sanitisation" do
    test "preserves allowed image type", %{conn: conn} do
      ClientMock
      |> expect(:request, fn :get, "/content", _, _, _ ->
        {:ok, 200, [{"content-type", "image/png"}], %{url: "/content"}}
      end)
      |> expect(:stream_body, fn _ -> :done end)

      conn = ReverseProxy.call(conn, "/content")

      assert conn.status == 200
      assert Conn.get_resp_header(conn, "content-type") == ["image/png"]
    end

    test "preserves allowed video type", %{conn: conn} do
      ClientMock
      |> expect(:request, fn :get, "/content", _, _, _ ->
        {:ok, 200, [{"content-type", "video/mp4"}], %{url: "/content"}}
      end)
      |> expect(:stream_body, fn _ -> :done end)

      conn = ReverseProxy.call(conn, "/content")

      assert conn.status == 200
      assert Conn.get_resp_header(conn, "content-type") == ["video/mp4"]
    end

    test "sanitizes ActivityPub content type", %{conn: conn} do
      ClientMock
      |> expect(:request, fn :get, "/content", _, _, _ ->
        {:ok, 200, [{"content-type", "application/activity+json"}], %{url: "/content"}}
      end)
      |> expect(:stream_body, fn _ -> :done end)

      conn = ReverseProxy.call(conn, "/content")

      assert conn.status == 200
      assert Conn.get_resp_header(conn, "content-type") == ["application/octet-stream"]
    end

    test "sanitizes LD-JSON content type", %{conn: conn} do
      ClientMock
      |> expect(:request, fn :get, "/content", _, _, _ ->
        {:ok, 200, [{"content-type", "application/ld+json"}], %{url: "/content"}}
      end)
      |> expect(:stream_body, fn _ -> :done end)

      conn = ReverseProxy.call(conn, "/content")

      assert conn.status == 200
      assert Conn.get_resp_header(conn, "content-type") == ["application/octet-stream"]
    end
  end
end
