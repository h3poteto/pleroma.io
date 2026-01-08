# Pleroma: A lightweight social networking server
# Copyright © Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.EmojiPackControllerDownloadZipTest do
  use Pleroma.Web.ConnCase, async: false

  import Tesla.Mock
  import Pleroma.Factory

  setup_all do
    # Create a base temp directory for this test module
    base_temp_dir = Path.join(System.tmp_dir!(), "emoji_test_#{Ecto.UUID.generate()}")

    # Clean up when all tests in module are done
    on_exit(fn ->
      File.rm_rf!(base_temp_dir)
    end)

    {:ok, %{base_temp_dir: base_temp_dir}}
  end

  setup %{base_temp_dir: base_temp_dir} do
    # Create a unique subdirectory for each test
    test_id = Ecto.UUID.generate()
    temp_dir = Path.join(base_temp_dir, test_id)
    emoji_dir = Path.join(temp_dir, "emoji")

    # Create the directory structure
    File.mkdir_p!(emoji_dir)

    # Configure this test to use the temp directory
    clear_config([:instance, :static_dir], temp_dir)

    admin = insert(:user, is_admin: true)
    token = insert(:oauth_admin_token, user: admin)

    admin_conn =
      build_conn()
      |> assign(:user, admin)
      |> assign(:token, token)

    Pleroma.Emoji.reload()

    {:ok, %{admin_conn: admin_conn, emoji_path: emoji_dir}}
  end

  describe "POST /api/pleroma/emoji/packs/download_zip" do
    setup do
      clear_config([:instance, :admin_privileges], [:emoji_manage_emoji])
    end

    test "creates pack from uploaded ZIP file", %{admin_conn: admin_conn, emoji_path: emoji_path} do
      # Create a test ZIP file with emojis
      {:ok, zip_path} = create_test_emoji_zip()

      upload = %Plug.Upload{
        content_type: "application/zip",
        path: zip_path,
        filename: "test_pack.zip"
      }

      assert admin_conn
             |> put_req_header("content-type", "multipart/form-data")
             |> post("/api/pleroma/emoji/packs/download_zip", %{
               name: "test_zip_pack",
               file: upload
             })
             |> json_response_and_validate_schema(200) == "ok"

      # Verify pack was created
      assert File.exists?("#{emoji_path}/test_zip_pack/pack.json")
      assert File.exists?("#{emoji_path}/test_zip_pack/test_emoji.png")

      # Verify pack.json contents
      {:ok, pack_json} = File.read("#{emoji_path}/test_zip_pack/pack.json")
      pack_data = Jason.decode!(pack_json)

      assert pack_data["files"]["test_emoji"] == "test_emoji.png"
      assert pack_data["pack"]["src_sha256"] != nil

      # Clean up
      File.rm!(zip_path)
    end

    test "creates pack from URL", %{admin_conn: admin_conn, emoji_path: emoji_path} do
      # Mock HTTP request to download ZIP
      {:ok, zip_path} = create_test_emoji_zip()
      {:ok, zip_data} = File.read(zip_path)

      mock(fn
        %{method: :get, url: "https://example.com/emoji_pack.zip"} ->
          %Tesla.Env{status: 200, body: zip_data}
      end)

      assert admin_conn
             |> put_req_header("content-type", "multipart/form-data")
             |> post("/api/pleroma/emoji/packs/download_zip", %{
               name: "test_zip_pack_url",
               url: "https://example.com/emoji_pack.zip"
             })
             |> json_response_and_validate_schema(200) == "ok"

      # Verify pack was created
      assert File.exists?("#{emoji_path}/test_zip_pack_url/pack.json")
      assert File.exists?("#{emoji_path}/test_zip_pack_url/test_emoji.png")

      # Verify pack.json has URL as source
      {:ok, pack_json} = File.read("#{emoji_path}/test_zip_pack_url/pack.json")
      pack_data = Jason.decode!(pack_json)

      assert pack_data["pack"]["src"] == "https://example.com/emoji_pack.zip"
      assert pack_data["pack"]["src_sha256"] != nil

      # Clean up
      File.rm!(zip_path)
    end

    test "refuses to overwrite existing pack", %{admin_conn: admin_conn, emoji_path: emoji_path} do
      # Create existing pack
      pack_path = Path.join(emoji_path, "test_zip_pack")
      File.mkdir_p!(pack_path)
      File.write!(Path.join(pack_path, "pack.json"), Jason.encode!(%{files: %{}}))

      {:ok, zip_path} = create_test_emoji_zip()

      upload = %Plug.Upload{
        content_type: "application/zip",
        path: zip_path,
        filename: "test_pack.zip"
      }

      assert admin_conn
             |> put_req_header("content-type", "multipart/form-data")
             |> post("/api/pleroma/emoji/packs/download_zip", %{
               name: "test_zip_pack",
               file: upload
             })
             |> json_response_and_validate_schema(400) == %{
               "error" => "Pack already exists, refusing to import test_zip_pack"
             }

      # Clean up
      File.rm!(zip_path)
    end

    test "handles invalid ZIP file", %{admin_conn: admin_conn} do
      # Create invalid ZIP file
      invalid_zip_path = Path.join(System.tmp_dir!(), "invalid.zip")
      File.write!(invalid_zip_path, "not a zip file")

      upload = %Plug.Upload{
        content_type: "application/zip",
        path: invalid_zip_path,
        filename: "invalid.zip"
      }

      assert admin_conn
             |> put_req_header("content-type", "multipart/form-data")
             |> post("/api/pleroma/emoji/packs/download_zip", %{
               name: "test_invalid_pack",
               file: upload
             })
             |> json_response_and_validate_schema(400) == %{
               "error" => "Could not unzip pack"
             }

      # Clean up
      File.rm!(invalid_zip_path)
    end

    test "handles URL download failure", %{admin_conn: admin_conn} do
      mock(fn
        %{method: :get, url: "https://example.com/bad_pack.zip"} ->
          %Tesla.Env{status: 404, body: "Not found"}
      end)

      assert admin_conn
             |> put_req_header("content-type", "multipart/form-data")
             |> post("/api/pleroma/emoji/packs/download_zip", %{
               name: "test_bad_url_pack",
               url: "https://example.com/bad_pack.zip"
             })
             |> json_response_and_validate_schema(400) == %{
               "error" => "Could not download pack"
             }
    end

    test "requires either file or URL parameter", %{admin_conn: admin_conn} do
      assert admin_conn
             |> put_req_header("content-type", "multipart/form-data")
             |> post("/api/pleroma/emoji/packs/download_zip", %{
               name: "test_no_source_pack"
             })
             |> json_response_and_validate_schema(400) == %{
               "error" => "Neither file nor URL was present in the request"
             }
    end

    test "returns error when pack name is empty", %{admin_conn: admin_conn} do
      {:ok, zip_path} = create_test_emoji_zip()

      upload = %Plug.Upload{
        content_type: "application/zip",
        path: zip_path,
        filename: "test_pack.zip"
      }

      assert admin_conn
             |> put_req_header("content-type", "multipart/form-data")
             |> post("/api/pleroma/emoji/packs/download_zip", %{
               name: "",
               file: upload
             })
             |> json_response_and_validate_schema(400) == %{
               "error" => "Pack name cannot be empty"
             }

      # Clean up
      File.rm!(zip_path)
    end

    test "returns error when unable to create pack directory", %{
      admin_conn: admin_conn,
      emoji_path: emoji_path
    } do
      # Make the emoji directory read-only to trigger mkdir_p failure

      # Save original permissions
      {:ok, %{mode: original_mode}} = File.stat(emoji_path)

      # Make emoji directory read-only (no write permission)
      File.chmod!(emoji_path, 0o555)

      {:ok, zip_path} = create_test_emoji_zip()

      upload = %Plug.Upload{
        content_type: "application/zip",
        path: zip_path,
        filename: "test_pack.zip"
      }

      # Try to create a pack in the read-only emoji directory
      assert admin_conn
             |> put_req_header("content-type", "multipart/form-data")
             |> post("/api/pleroma/emoji/packs/download_zip", %{
               name: "test_readonly_pack",
               file: upload
             })
             |> json_response_and_validate_schema(400) == %{
               "error" => "Could not create the pack directory"
             }

      # Clean up - restore original permissions
      File.chmod!(emoji_path, original_mode)
      File.rm!(zip_path)
    end

    test "preserves existing pack.json if present in ZIP", %{
      admin_conn: admin_conn,
      emoji_path: emoji_path
    } do
      # Create ZIP with pack.json
      {:ok, zip_path} = create_test_emoji_zip_with_pack_json()

      upload = %Plug.Upload{
        content_type: "application/zip",
        path: zip_path,
        filename: "test_pack_with_json.zip"
      }

      assert admin_conn
             |> put_req_header("content-type", "multipart/form-data")
             |> post("/api/pleroma/emoji/packs/download_zip", %{
               name: "test_zip_pack_with_json",
               file: upload
             })
             |> json_response_and_validate_schema(200) == "ok"

      # Verify original pack.json was preserved
      {:ok, pack_json} = File.read("#{emoji_path}/test_zip_pack_with_json/pack.json")
      pack_data = Jason.decode!(pack_json)

      assert pack_data["pack"]["description"] == "Test pack from ZIP"
      assert pack_data["pack"]["license"] == "Test License"

      # Clean up
      File.rm!(zip_path)
    end

    test "rejects malicious pack names", %{admin_conn: admin_conn} do
      {:ok, zip_path} = create_test_emoji_zip()

      upload = %Plug.Upload{
        content_type: "application/zip",
        path: zip_path,
        filename: "test_pack.zip"
      }

      # Test path traversal attempts
      malicious_names = ["../evil", "../../evil", ".", "..", "evil/../../../etc"]

      Enum.each(malicious_names, fn name ->
        assert_raise RuntimeError, ~r/Invalid or malicious pack name/, fn ->
          admin_conn
          |> put_req_header("content-type", "multipart/form-data")
          |> post("/api/pleroma/emoji/packs/download_zip", %{
            name: name,
            file: upload
          })
        end
      end)

      # Clean up
      File.rm!(zip_path)
    end
  end

  defp create_test_emoji_zip do
    tmp_dir = System.tmp_dir!()
    zip_path = Path.join(tmp_dir, "test_emoji_pack_#{:rand.uniform(10000)}.zip")

    # 1x1 pixel PNG
    png_data =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
      )

    files = [
      {~c"test_emoji.png", png_data},
      # Will be treated as GIF based on extension
      {~c"another_emoji.gif", png_data}
    ]

    {:ok, {_name, zip_binary}} = :zip.zip(~c"test_pack.zip", files, [:memory])
    File.write!(zip_path, zip_binary)

    {:ok, zip_path}
  end

  defp create_test_emoji_zip_with_pack_json do
    tmp_dir = System.tmp_dir!()
    zip_path = Path.join(tmp_dir, "test_emoji_pack_json_#{:rand.uniform(10000)}.zip")

    png_data =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
      )

    pack_json =
      Jason.encode!(%{
        pack: %{
          description: "Test pack from ZIP",
          license: "Test License"
        },
        files: %{
          "test_emoji" => "test_emoji.png"
        }
      })

    files = [
      {~c"test_emoji.png", png_data},
      {~c"pack.json", pack_json}
    ]

    {:ok, {_name, zip_binary}} = :zip.zip(~c"test_pack.zip", files, [:memory])
    File.write!(zip_path, zip_binary)

    {:ok, zip_path}
  end
end
