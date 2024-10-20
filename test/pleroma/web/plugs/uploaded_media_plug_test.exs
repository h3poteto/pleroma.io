# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.UploadedMediaPlugTest do
  use Pleroma.Web.ConnCase, async: true

  alias Pleroma.UnstubbedConfigMock, as: ConfigMock
  alias Pleroma.Upload

  import Mox

  defp upload_file(context) do
    ConfigMock
    |> stub_with(Pleroma.Test.StaticConfig)

    Pleroma.DataCase.ensure_local_uploader(context)

    File.cp!("test/fixtures/image.jpg", "test/fixtures/image_tmp.jpg")

    file = %Plug.Upload{
      content_type: "image/jpeg",
      path: Path.absname("test/fixtures/image_tmp.jpg"),
      filename: "nice_tf.jpg"
    }

    {:ok, data} = Upload.store(file)
    [%{"href" => attachment_url} | _] = data["url"]
    [attachment_url: attachment_url]
  end

  setup_all :upload_file

  setup do
    ConfigMock
    |> stub_with(Pleroma.Test.StaticConfig)

    :ok
  end

  test "does not send Content-Disposition header when name param is not set", %{
    attachment_url: attachment_url
  } do
    conn = get(build_conn(), attachment_url)
    refute Enum.any?(conn.resp_headers, &(elem(&1, 0) == "content-disposition"))
  end

  test "sends Content-Disposition header when name param is set", %{
    attachment_url: attachment_url
  } do
    conn = get(build_conn(), attachment_url <> ~s[?name="cofe".gif])

    assert Enum.any?(
             conn.resp_headers,
             &(&1 == {"content-disposition", ~s[inline; filename="\\"cofe\\".gif"]})
           )
  end
end
