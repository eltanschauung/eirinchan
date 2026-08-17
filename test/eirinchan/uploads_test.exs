defmodule Eirinchan.UploadsTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Uploads
  import Eirinchan.UploadsFixtures, only: [raw_upload_fixture: 2]

  test "describe preserves spaces in original display filenames" do
    upload = raw_upload_fixture("two words.txt", "hello")
    on_exit(fn -> File.rm(upload.path) end)

    assert {:ok, %{file_name: "two words.txt"}} = Uploads.describe(upload, %{})
  end

  test "swf uploads require a flash MIME type" do
    assert Uploads.compatible_with_extension?(".swf", "application/x-shockwave-flash")
    assert Uploads.compatible_with_extension?(".swf", "application/vnd.adobe.flash.movie")
    refute Uploads.compatible_with_extension?(".swf", "text/html")
  end

  test "ogg uploads require an ogg MIME type" do
    assert Uploads.compatible_with_extension?(".ogg", "audio/ogg")
    assert Uploads.compatible_with_extension?(".ogg", "application/ogg")
    refute Uploads.compatible_with_extension?(".ogg", "text/html")
  end

  test "heic uploads require a HEIF image MIME type" do
    assert Uploads.compatible_with_extension?(".heic", "image/heic")
    assert Uploads.compatible_with_extension?(".heic", "image/heif")
    refute Uploads.compatible_with_extension?(".heic", "image/jpeg")
  end

  test "preflight validates the HEIC container signature" do
    heic = raw_upload_fixture("safe.heic", <<0, 0, 0, 28, "ftypheic", 0, 0, 0, 0, "mif1heic">>)
    disguised = raw_upload_fixture("disguised.heic", <<0xFF, 0xD8, 0xFF, 0, 0, 0, 0, 0>>)
    on_exit(fn -> File.rm(heic.path) end)
    on_exit(fn -> File.rm(disguised.path) end)

    config = %{allowed_ext_files: [".heic"], allowed_ext_files_op: nil, max_filesize: 1024}

    assert :ok = Uploads.preflight_upload(heic, config)
    assert {:error, :mime_exploit} = Uploads.preflight_upload(disguised, config)
  end

  test "preflight rejects a dangerous decoder format disguised as an allowed image" do
    upload = raw_upload_fixture("disguised.png", <<0x50, 0x43, 0x44, 0x5F, 0x49, 0x50, 0x49>>)
    on_exit(fn -> File.rm(upload.path) end)

    config = %{allowed_ext_files: [".png"], allowed_ext_files_op: nil, max_filesize: 1024}

    assert {:error, :mime_exploit} = Uploads.preflight_upload(upload, config)
  end

  test "preflight accepts signatures for configured image and video containers" do
    png = raw_upload_fixture("safe.png", <<0x89, "PNG\r\n", 0x1A, "\n", 0, 0, 0, 0>>)
    webm = raw_upload_fixture("safe.webm", <<0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0>>)
    on_exit(fn -> File.rm(png.path) end)
    on_exit(fn -> File.rm(webm.path) end)

    config = %{
      allowed_ext_files: [".png", ".webm"],
      allowed_ext_files_op: nil,
      max_filesize: 1024
    }

    assert :ok = Uploads.preflight_upload(png, config)
    assert :ok = Uploads.preflight_upload(webm, config)
  end

  test "preflight rejects extensions before invoking media parsers" do
    upload = raw_upload_fixture("payload.pcd", "not an allowed image")
    on_exit(fn -> File.rm(upload.path) end)

    config = %{allowed_ext_files: [".png"], allowed_ext_files_op: nil, max_filesize: 1024}

    assert {:error, :invalid_file_type} = Uploads.preflight_upload(upload, config)
  end

  test "video upload validation accepts av1 webm streams" do
    assert :ok ==
             Uploads.video_allowed_for_upload?(
               %{
                 "format" => %{"format_name" => "matroska,webm", "duration" => "3.5"},
                 "streams" => [
                   %{
                     "codec_type" => "video",
                     "codec_name" => "av1",
                     "width" => 1280,
                     "height" => 720
                   }
                 ]
               },
               ".webm",
               %{webm: %{allow_audio: true, max_length: 720}}
             )
  end

  test "video upload validation accepts opus audio when audio is allowed" do
    assert :ok ==
             Uploads.video_allowed_for_upload?(
               %{
                 "format" => %{"format_name" => "mov,mp4,m4a,3gp,3g2,mj2", "duration" => "5.0"},
                 "streams" => [
                   %{
                     "codec_type" => "video",
                     "codec_name" => "av1",
                     "width" => 1920,
                     "height" => 1080
                   },
                   %{
                     "codec_type" => "audio",
                     "codec_name" => "opus"
                   }
                 ]
               },
               ".mp4",
               %{webm: %{allow_audio: true, max_length: 720}}
             )
  end

  test "video upload validation rejects codecs outside the processing allowlist" do
    assert {:error, :invalid_video} ==
             Uploads.video_allowed_for_upload?(
               %{
                 "format" => %{"format_name" => "mov,mp4", "duration" => "5.0"},
                 "streams" => [
                   %{
                     "codec_type" => "video",
                     "codec_name" => "magicyuv",
                     "width" => 640,
                     "height" => 480
                   }
                 ]
               },
               ".mp4",
               %{webm: %{allow_audio: true, max_length: 720}}
             )
  end

  test "video upload validation rejects unexpected audio codecs" do
    assert {:error, :invalid_video} ==
             Uploads.video_allowed_for_upload?(
               %{
                 "format" => %{"format_name" => "mov,mp4", "duration" => "5.0"},
                 "streams" => [
                   %{"codec_type" => "video", "codec_name" => "h264", "width" => 640, "height" => 480},
                   %{"codec_type" => "audio", "codec_name" => "flac"}
                 ]
               },
               ".mp4",
               %{webm: %{allow_audio: true, max_length: 720}}
             )
  end
end
