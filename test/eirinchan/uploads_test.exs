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
end
