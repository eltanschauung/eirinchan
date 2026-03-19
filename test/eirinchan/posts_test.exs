defmodule Eirinchan.TestFailingPostFileRepo do
  alias Eirinchan.Posts.PostFile
  alias Eirinchan.Repo

  def transaction(fun), do: Repo.transaction(fun)
  def rollback(reason), do: Repo.rollback(reason)
  def update(changeset), do: Repo.update(changeset)
  def all(queryable), do: Repo.all(queryable)
  def one(queryable), do: Repo.one(queryable)
  def aggregate(queryable, aggregate, field), do: Repo.aggregate(queryable, aggregate, field)
  def exists?(queryable), do: Repo.exists?(queryable)
  def preload(struct_or_structs, preloads), do: Repo.preload(struct_or_structs, preloads)
  def get_by(queryable, clauses), do: Repo.get_by(queryable, clauses)
  def delete(struct), do: Repo.delete(struct)

  def insert(%Ecto.Changeset{data: %PostFile{}} = changeset) do
    if Process.get(:fail_post_file_insert_once) do
      Process.delete(:fail_post_file_insert_once)
      {:error, Ecto.Changeset.add_error(changeset, :position, "forced failure")}
    else
      Repo.insert(changeset)
    end
  end

  def insert(changeset), do: Repo.insert(changeset)
end

defmodule Eirinchan.PostsTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.Antispam
  alias Eirinchan.Build
  alias Eirinchan.ModerationLog
  alias Eirinchan.Posts
  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Posts.Post
  alias Eirinchan.Repo
  alias Eirinchan.Runtime.Config
  import Ecto.Query

  defp post_config(board_overrides) do
    Config.compose(nil, %{}, board_overrides, request_host: "example.test")
  end

  defp post_request(board_uri) do
    %{referer: "http://example.test/#{board_uri}/index.html"}
  end

  defp exiftool_value(path, field) do
    {output, 0} = System.cmd("exiftool", ["-s3", "-#{field}", path], stderr_to_stdout: true)
    String.trim(output)
  end

  defp identify_value(path, format) do
    {output, 0} = System.cmd("identify", ["-format", format, path], stderr_to_stdout: true)
    String.trim(output)
  end

  defp icon_fixture(name, opts) do
    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-icon-#{System.unique_integer([:positive])}-#{Path.basename(name)}"
      )

    geometry = Keyword.get(opts, :geometry, "24x24")
    color = Keyword.get(opts, :color, "#336699")
    {_, 0} = System.cmd("convert", ["-size", geometry, "xc:#{color}", path])
    path
  end

  defp bundled_geoip_database_path do
    Application.app_dir(:eirinchan, "priv/geoip2/GeoLite2-Country.mmdb")
  end

  test "create_post creates an OP when no thread is supplied" do
    board = board_fixture()

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "name" => " anon ",
                 "subject" => " launch ",
                 "body" => "  first post  ",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.thread_id == nil
    assert thread.name == "anon"
    assert thread.subject == "launch"
    assert thread.body == "first post"
  end

  test "create_post creates a reply when a valid thread is supplied" do
    board = board_fixture()
    thread = thread_fixture(board)

    assert {:ok, reply, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "reply body",
                 "post" => "New Reply"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert reply.thread_id == thread.id
  end

  test "create_post stores nil ip_subnet when ip_nulling is enabled" do
    board = board_fixture()

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "post" => "New Topic"
               },
               config: post_config(Map.put(board.config_overrides || %{}, :ip_nulling, true)),
               request: Map.put(post_request(board.uri), :remote_ip, {203, 0, 113, 40})
             )

    assert thread.ip_subnet == nil
  end

  test "create_post keeps ip_subnet when ip_nulling_flags threshold is not met" do
    board = board_fixture()

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "user_flag" => "country",
                 "post" => "New Topic"
               },
               config:
                 post_config(
                   board.config_overrides
                   |> Kernel.||(%{})
                   |> Map.put(:ip_nulling, true)
                   |> Map.put(:ip_nulling_flags, 8)
                 ),
               request: Map.put(post_request(board.uri), :remote_ip, {203, 0, 113, 41})
             )

    assert thread.ip_subnet == "203.0.113.41"
  end

  test "create_post nulls ip_subnet when ip_nulling_flags threshold is met" do
    board = board_fixture()

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "user_flag" => "country,mokou",
                 "post" => "New Topic"
               },
               config:
                 post_config(
                   board.config_overrides
                   |> Kernel.||(%{})
                   |> Map.put(:ip_nulling, true)
                   |> Map.put(:ip_nulling_flags, 8)
                 ),
               request: Map.put(post_request(board.uri), :remote_ip, {203, 0, 113, 42})
             )

    assert thread.ip_subnet == nil
  end

  test "create_post accepts legacy post parameter aliases and mode=regist" do
    board = board_fixture()

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "name" => "anon",
                 "sub" => "legacy subject",
                 "com" => "legacy body",
                 "pwd" => "secretpw",
                 "mode" => "regist"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.subject == "legacy subject"
    assert thread.body == "legacy body"
    assert thread.password == "secretpw"

    assert {:ok, reply, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "resto" => Integer.to_string(PublicIds.public_id(thread)),
                 "message" => "legacy reply",
                 "mode" => "regist"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert reply.thread_id == thread.id
    assert reply.body == "legacy reply"
  end

  test "create_post stores upload metadata for image posts" do
    board = board_fixture()
    upload = upload_fixture("first.png", "png-bytes")

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.file_name == "first.png"
    assert thread.file_path =~ ~r|^/#{board.uri}/src/\d+\.png$|
    assert thread.thumb_path =~ ~r|^/#{board.uri}/thumb/\d+s\.png$|
    assert thread.file_type == "image/png"
    assert is_binary(thread.file_md5)
    assert thread.image_width == 16
    assert thread.image_height == 16

    stored_path = Eirinchan.Uploads.filesystem_path(thread.file_path)
    assert thread.file_size == File.stat!(stored_path).size

    assert File.exists?(stored_path)

    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.thumb_path))
  end

  test "list_catalog_page sorts full catalog before pagination when sorting by replies" do
    board =
      board_fixture(%{
        config_overrides: %{
          catalog_pagination: true,
          catalog_threads_per_page: 2
        }
      })

    [thread_a, thread_b, thread_c, thread_d] =
      Enum.map(["A", "B", "C", "D"], fn subject ->
        thread_fixture(board, %{subject: subject, body: subject <> " body"})
      end)

    for _ <- 1..4, do: reply_fixture(board, thread_a, %{body: "reply"})
    for _ <- 1..3, do: reply_fixture(board, thread_b, %{body: "reply"})
    for _ <- 1..2, do: reply_fixture(board, thread_c, %{body: "reply"})
    for _ <- 1..1, do: reply_fixture(board, thread_d, %{body: "reply"})

    Repo.update_all(from(p in Post, where: p.id == ^thread_a.id), set: [bump_at: ~N[2026-01-01 00:00:00]])
    Repo.update_all(from(p in Post, where: p.id == ^thread_b.id), set: [bump_at: ~N[2026-01-02 00:00:00]])
    Repo.update_all(from(p in Post, where: p.id == ^thread_c.id), set: [bump_at: ~N[2026-01-03 00:00:00]])
    Repo.update_all(from(p in Post, where: p.id == ^thread_d.id), set: [bump_at: ~N[2026-01-04 00:00:00]])

    {:ok, page_data} =
      Posts.list_catalog_page(board, 1,
        config: post_config(board.config_overrides),
        sort_by: "reply:desc"
      )

    assert Enum.map(page_data.threads, & &1.thread.subject) == ["A", "B"]
  end

  test "list_catalog_page filters catalog threads before pagination" do
    board =
      board_fixture(%{
        config_overrides: %{
          catalog_pagination: true,
          catalog_threads_per_page: 2
        }
      })

    alpha = thread_fixture(board, %{subject: "alpha", body: "matching body"})
    _beta = thread_fixture(board, %{subject: "beta", body: "other"})
    gamma = thread_fixture(board, %{subject: "gamma", body: "matching again"})

    {:ok, page_data} =
      Posts.list_catalog_page(board, 1,
        config: post_config(board.config_overrides),
        search: "matching"
      )

    assert Enum.map(page_data.threads, & &1.thread.id) == [gamma.id, alpha.id]
    assert page_data.total_pages == 1
  end

  test "create_post keeps jpg thumbnails as jpg" do
    board = board_fixture()
    upload = upload_fixture("photo.jpg", "jpg-bytes")

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "jpg post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.file_type == "image/jpeg"
    assert thread.thumb_path =~ ~r|^/#{board.uri}/thumb/\d+s\.jpg$|
  end

  test "create_post allows file-only replies without a body" do
    board = board_fixture()
    thread = thread_fixture(board)
    upload = upload_fixture("reply.png", "png-bytes")

    assert {:ok, reply, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => " \n\t ",
                 "file" => upload,
                 "post" => "New Reply"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert reply.thread_id == thread.id
    assert reply.body == ""
    assert reply.file_name == "reply.png"
  end

  test "create_post accepts configured YouTube embeds without files" do
    board = board_fixture()

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "watch this",
                 "embed" => "https://youtu.be/dQw4w9WgXcQ",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.embed == "https://youtu.be/dQw4w9WgXcQ"
    assert is_nil(thread.file_path)
    assert is_nil(thread.thumb_path)
  end

  test "create_post rejects invalid embed urls" do
    board = board_fixture()

    assert {:error, :invalid_embed} =
             Posts.create_post(
               board,
               %{
                 "body" => "watch this",
                 "embed" => "https://example.com/not-youtube",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post rejects ie mime type detection xss payloads on image uploads" do
    board = board_fixture()

    assert {:error, :mime_exploit} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" =>
                   raw_upload_fixture("exploit.png", "<html><script>alert(1)</script></html>"),
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post allows embed-only OPs when force_image_op is enabled" do
    board = board_fixture(%{config_overrides: %{force_image_op: true, force_body_op: false}})
    config = post_config(board.config_overrides)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "embed" => "https://youtu.be/dQw4w9WgXcQ",
                 "post" => config.button_newtopic
               },
               config: config,
               request: post_request(board.uri)
             )

    assert thread.embed == "https://youtu.be/dQw4w9WgXcQ"
  end

  test "create_post moves upload temp files into board storage" do
    board = board_fixture()
    upload = upload_fixture("moved.png", "move-me")
    source_path = upload.path

    assert File.exists?(source_path)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    refute File.exists?(source_path)
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
  end

  test "create_post falls back to copy-delete when renaming upload temp files fails" do
    board = board_fixture()
    upload = upload_fixture("copied.png", "copy-me")
    source_path = upload.path

    Process.put(:eirinchan_force_rename_failure, true)
    on_exit(fn -> Process.delete(:eirinchan_force_rename_failure) end)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    refute File.exists?(source_path)
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
  end

  test "create_post stores placeholder thumbnails for allowed non-image uploads" do
    board =
      board_fixture(%{
        config_overrides: %{allowed_ext_files: [".png", ".jpg", ".jpeg", ".gif", ".txt"]}
      })

    upload = raw_upload_fixture("notes.txt", "hello")

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.file_name == "notes.txt"
    assert thread.file_path =~ ~r|^/#{board.uri}/src/\d+\.txt$|
    assert thread.thumb_path =~ ~r|^/#{board.uri}/thumb/\d+s\.png$|
    assert thread.file_size == byte_size("hello")
    assert thread.file_type == "text/plain"
    assert thread.image_width == nil
    assert thread.image_height == nil
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.thumb_path))
  end

  test "create_post uses OP-specific thumbnail dimensions for thread starters" do
    board =
      board_fixture(%{
        config_overrides: %{
          thumb_width: 40,
          thumb_height: 40,
          thumb_op_width: 80,
          thumb_op_height: 80
        }
      })

    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload_fixture("thread.png", geometry: "120x60"),
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )

    assert {:ok, reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "reply body",
                 "file" => upload_fixture("reply.png", geometry: "120x60"),
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert identify_value(Eirinchan.Uploads.filesystem_path(thread.thumb_path), "%wx%h") ==
             "80x40"

    assert identify_value(Eirinchan.Uploads.filesystem_path(reply.thumb_path), "%wx%h") == "40x20"
  end

  test "create_post uses configured file icons for non-image thumbnails" do
    icon_path = icon_fixture("text.png", geometry: "24x24", color: "#113355")

    board =
      board_fixture(%{
        config_overrides: %{
          allowed_ext_files: [".png", ".jpg", ".jpeg", ".gif", ".txt"],
          file_thumb: Path.join(Path.dirname(icon_path), "%s"),
          file_icons: %{".txt" => Path.basename(icon_path)}
        }
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => raw_upload_fixture("notes.txt", "hello"),
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    thumb_path = Eirinchan.Uploads.filesystem_path(thread.thumb_path)

    assert File.read!(thumb_path) == File.read!(icon_path)
    assert identify_value(thumb_path, "%wx%h") == "24x24"
  end

  test "create_post stores extra files from a multi-file upload" do
    board = board_fixture()

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "files" => [
                   upload_fixture("first.png", "first"),
                   upload_fixture("second.gif", "second")
                 ],
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.file_name == "first.png"
    assert length(thread.extra_files) == 1

    [extra] = thread.extra_files
    assert extra.position == 1
    assert extra.file_name == "second.gif"
    assert extra.file_path =~ ~r|^/#{board.uri}/src/\d+-1\.gif$|
    assert extra.thumb_path =~ ~r|^/#{board.uri}/thumb/\d+-1s\.gif$|
  end

  test "create_post generates jpg thumbnails for video uploads" do
    board = board_fixture()
    upload = video_upload_fixture("clip.webm")

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "video post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.file_type == "video/webm"
    assert thread.thumb_path =~ ~r|^/#{board.uri}/thumb/\d+s\.jpg$|
    assert thread.image_width == 64
    assert thread.image_height == 48
  end

  test "create_post generates thumbnails for animated webp uploads" do
    board = board_fixture()
    upload = animated_webp_upload_fixture("clip.webp")

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "animated webp post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.file_type == "image/webp"
    assert thread.thumb_path =~ ~r|^/#{board.uri}/thumb/\d+s\.png$|
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.thumb_path))
  end

  test "create_post marks spoiler uploads on primary and extra files" do
    board = board_fixture()

    assert {:ok, thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "files" => [
                   upload_fixture("first.png", "first"),
                   upload_fixture("second.gif", "second")
                 ],
                 "spoiler" => "1",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.spoiler == true
    assert [extra] = thread.extra_files
    assert extra.spoiler == true
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.thumb_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(extra.thumb_path))
  end

  test "create_post supports OP-specific extension allowlists" do
    board =
      board_fixture(%{
        config_overrides: %{allowed_ext_files: [".png", ".jpg"], allowed_ext_files_op: [".txt"]}
      })

    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "file" => raw_upload_fixture("notes.txt", "hello"),
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )

    assert thread.file_type == "text/plain"

    assert {:error, :invalid_file_type} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply body",
                 "file" => raw_upload_fixture("reply.txt", "hello"),
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )
  end

  test "create_post rejects extension-spoofed non-image uploads" do
    board =
      board_fixture(%{
        config_overrides: %{allowed_ext_files: [".png", ".jpg", ".jpeg", ".gif", ".txt"]}
      })

    spoofed_upload =
      duplicate_upload_fixture(upload_fixture("real.png", "png-bytes"), "notes.txt")

    assert {:error, :invalid_file_type} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => spoofed_upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post canonicalizes stored filenames without using the display truncation limit" do
    board = board_fixture(%{config_overrides: %{max_filename_display_length: 12}})

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" =>
                   upload_fixture(
                     "  a very long*&^% display filename with spaces.PNG  ",
                     "png-bytes"
                   ),
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.file_name == "a_very_long_display_filename_with_spaces.png"
  end

  test "create_post always strips EXIF metadata from stored jpeg files" do
    board = board_fixture()
    upload = upload_fixture("meta.jpg", geometry: "10x10", artist: "fixture-artist")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    stored_path = Eirinchan.Uploads.filesystem_path(thread.file_path)

    assert exiftool_value(stored_path, "Artist") == ""
  end

  test "create_post copies small png files directly into thumbnails when minimum_copy_resize is enabled" do
    board = board_fixture(%{config_overrides: %{minimum_copy_resize: true}})
    upload = upload_fixture("small.png", geometry: "12x8")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    stored_path = Eirinchan.Uploads.filesystem_path(thread.file_path)
    thumb_path = Eirinchan.Uploads.filesystem_path(thread.thumb_path)

    assert File.read!(stored_path) == File.read!(thumb_path)
    assert identify_value(thumb_path, "%wx%h") == "12x8"
  end

  test "create_post auto-orients stored jpeg files and refreshes dimensions" do
    board = board_fixture()
    upload = upload_fixture("rotated.jpg", geometry: "12x8", orientation: "Rotate 90 CW")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    stored_path = Eirinchan.Uploads.filesystem_path(thread.file_path)

    assert {thread.image_width, thread.image_height} == {8, 12}
    assert identify_value(stored_path, "%wx%h") == "8x12"
    assert exiftool_value(stored_path, "Orientation") == ""
  end

  test "create_post strips metadata and normalizes orientation in one upload path" do
    board = board_fixture()

    upload =
      upload_fixture("redrawn.jpg",
        geometry: "12x8",
        orientation: "Rotate 90 CW",
        artist: "fixture-artist"
      )

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    stored_path = Eirinchan.Uploads.filesystem_path(thread.file_path)

    assert {thread.image_width, thread.image_height} == {8, 12}
    assert identify_value(stored_path, "%wx%h") == "8x12"
    assert exiftool_value(stored_path, "Artist") == ""
    assert exiftool_value(stored_path, "Orientation") == ""
  end

  test "create_post early-404 prunes old low-reply threads after board overflow" do
    board =
      board_fixture(%{
        config_overrides: %{
          early_404: true,
          early_404_page: 1,
          early_404_replies: 2,
          threads_per_page: 1,
          max_pages: 5
        }
      })

    config = post_config(board.config_overrides)

    {:ok, old_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "old", "post" => "New Topic"},
        config: config,
        request: post_request(board.uri)
      )

    {:ok, _new_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "new", "post" => "New Topic"},
        config: config,
        request: post_request(board.uri)
      )

    assert {:error, :not_found} = Posts.get_post(board, PublicIds.public_id(old_thread))
  end

  test "create_post keeps old threads past early-404 when reply threshold is met" do
    board =
      board_fixture(%{
        config_overrides: %{
          early_404: true,
          early_404_page: 1,
          early_404_replies: 1,
          threads_per_page: 1,
          max_pages: 5
        }
      })

    config = post_config(board.config_overrides)

    {:ok, old_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "old", "post" => "New Topic"},
        config: config,
        request: post_request(board.uri)
      )

    {:ok, _reply, _meta} =
      Posts.create_post(
        board,
        %{"body" => "bump", "thread" => Integer.to_string(old_thread.id), "post" => "Reply"},
        config: config,
        request: post_request(board.uri)
      )

    {:ok, _new_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "new", "post" => "New Topic"},
        config: config,
        request: post_request(board.uri)
      )

    assert {:ok, _thread} = Posts.get_post(board, PublicIds.public_id(old_thread))
  end

  test "create_post logs early-404 thread deletions to the moderation log" do
    board =
      board_fixture(%{
        config_overrides: %{
          early_404: true,
          early_404_page: 1,
          early_404_replies: 2,
          threads_per_page: 1,
          max_pages: 5
        }
      })

    config = post_config(board.config_overrides)

    {:ok, old_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "old", "post" => "New Topic"},
        config: config,
        request: post_request(board.uri)
      )

    {:ok, new_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "new", "post" => "New Topic"},
        config: config,
        request: post_request(board.uri)
      )

    assert ModerationLog.list_recent_entries_by_text(
             "Automatically deleting thread ##{PublicIds.public_id(old_thread)} due to new thread ##{PublicIds.public_id(new_thread)}",
             board_uri: board.uri,
             limit: 1
           ) != []
  end

  test "create_post prunes overflow threads when max pages are exceeded" do
    board =
      board_fixture(%{
        config_overrides: %{
          early_404: false,
          threads_per_page: 1,
          max_pages: 1,
          flood_time: 0,
          flood_time_ip: 0,
          flood_time_same: 0
        }
      })

    config = post_config(board.config_overrides)
    request = Map.put(post_request(board.uri), :remote_ip, {203, 0, 113, 40})

    {:ok, old_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "old", "post" => "New Topic"},
        config: config,
        request: request,
        repo: Repo
      )

    Process.sleep(1000)

    {:ok, new_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "new", "post" => "New Topic"},
        config: config,
        request: request,
        repo: Repo
      )

    assert {:error, :not_found} =
             Posts.get_post(board, PublicIds.public_id(old_thread), repo: Repo)

    assert {:ok, _thread} = Posts.get_post(board, new_thread.id, repo: Repo)
  end

  test "create_post staged early-404 raises thresholds by page" do
    board =
      board_fixture(%{
        config_overrides: %{
          early_404: true,
          early_404_page: 1,
          early_404_replies: 2,
          early_404_staged: true,
          threads_per_page: 1,
          max_pages: 5,
          flood_time: 0,
          flood_time_ip: 0,
          flood_time_same: 0
        }
      })

    config = post_config(board.config_overrides)
    request = Map.put(post_request(board.uri), :remote_ip, {203, 0, 113, 41})

    {:ok, staged_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "staged survivor", "post" => "New Topic"},
        config: config,
        request: request,
        repo: Repo
      )

    for _ <- 1..4 do
      assert {:ok, _reply, _meta} =
               Posts.create_post(
                 board,
                 %{
                   "body" => "sage",
                   "email" => "sage",
                   "thread" => Integer.to_string(staged_thread.id),
                   "post" => "Reply"
                 },
                 config: config,
                 request: request,
                 repo: Repo
               )
    end

    Process.sleep(1000)

    {:ok, doomed_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "doomed", "post" => "New Topic"},
        config: config,
        request: request,
        repo: Repo
      )

    Process.sleep(1000)

    {:ok, _newest_thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "newest", "post" => "New Topic"},
        config: config,
        request: request,
        repo: Repo
      )

    assert {:error, :not_found} = Posts.get_post(board, doomed_thread.id, repo: Repo)
    assert {:ok, _thread} = Posts.get_post(board, staged_thread.id, repo: Repo)
  end

  test "create_post fetches remote uploads when url uploads are enabled" do
    board =
      board_fixture(%{
        config_overrides: %{upload_by_url_enabled: true, upload_by_url_allow_private_hosts: true}
      })

    source_upload = upload_fixture("remote.png", "remote-image")
    server = serve_upload_fixture(File.read!(source_upload.path), "remote.png")
    on_exit(server.stop)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file_url" => server.url,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.file_name == "remote.png"
    assert thread.file_type == "image/png"
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
  end

  test "create_post rejects private remote upload hosts by default" do
    board = board_fixture(%{config_overrides: %{upload_by_url_enabled: true}})
    source_upload = upload_fixture("remote.png", "remote-image")
    server = serve_upload_fixture(File.read!(source_upload.path), "remote.png")
    on_exit(server.stop)

    assert {:error, :upload_failed} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file_url" => server.url,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post rejects remote uploads larger than max_filesize" do
    board =
      board_fixture(%{
        config_overrides: %{
          upload_by_url_enabled: true,
          upload_by_url_allow_private_hosts: true,
          max_filesize: 128
        }
      })

    source_upload = upload_fixture("remote.png", content: String.duplicate("x", 1024))
    server = serve_upload_fixture(File.read!(source_upload.path), "remote.png")
    on_exit(server.stop)

    assert {:error, :upload_failed} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file_url" => server.url,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post removes stored files when a later file insert fails" do
    board = board_fixture()
    File.rm_rf!(Path.join(Eirinchan.Build.board_root(), board.uri))
    Process.put(:fail_post_file_insert_once, true)

    assert {:error, %Ecto.Changeset{}} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "files" => [
                   upload_fixture("first.png", "first"),
                   upload_fixture("second.gif", "second")
                 ],
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri),
               repo: Eirinchan.TestFailingPostFileRepo
             )

    refute Repo.exists?(from(post in Post, where: post.board_id == ^board.id))
    assert Path.wildcard(Path.join(Eirinchan.Build.board_root(), "#{board.uri}/src/*")) == []
    assert Path.wildcard(Path.join(Eirinchan.Build.board_root(), "#{board.uri}/thumb/*")) == []
  end

  test "create_post rejects replies to missing threads" do
    board = board_fixture()

    assert {:error, :thread_not_found} =
             Posts.create_post(
               board,
               %{
                 "thread" => "999999",
                 "body" => "reply body",
                 "post" => "New Reply"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post rejects an invalid referer" do
    board = board_fixture()

    assert {:error, :invalid_referer} =
             Posts.create_post(board, %{"body" => "first post", "post" => "New Topic"},
               config: post_config(board.config_overrides),
               request: %{referer: "http://bad.example/elsewhere"}
             )
  end

  test "create_post enforces board lock and body requirements from config" do
    board = board_fixture(%{config_overrides: %{board_locked: true, force_body_op: true}})

    assert {:error, :board_locked} =
             Posts.create_post(board, %{"body" => "first post", "post" => "New Topic"},
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    unlocked = %{board | config_overrides: %{force_body_op: true}}

    assert {:error, :body_required} =
             Posts.create_post(unlocked, %{"body" => "   ", "post" => "New Topic"},
               config: post_config(unlocked.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post enforces max body length and line count" do
    board = board_fixture(%{config_overrides: %{max_body: 5, maximum_lines: 2}})
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:error, :body_too_long} =
             Posts.create_post(
               board,
               %{"body" => "123456", "post" => "New Topic"},
               config: config,
               request: request
             )

    assert {:error, :too_many_lines} =
             Posts.create_post(
               board,
               %{"body" => "a\nb\nc", "post" => "New Topic"},
               config: config,
               request: request
             )
  end

  test "create_post stores a normalized allowed user flag" do
    board =
      board_fixture(%{
        config_overrides: %{user_flag: true, user_flags: %{"sau" => "Sauce", "spc" => "Space"}}
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "user_flag" => "  SAU ",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.flag_codes == ["sau"]
    assert thread.flag_alts == ["Sauce"]
  end

  test "create_post uses us fallback when user_flag is submitted blank" do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          default_user_flag: "country",
          country_flag_fallback: %{code: "us", name: "United States"},
          user_flags: %{}
        }
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "flag fallback", "user_flag" => "", "post" => "New Thread"},
               config: post_config(board.config_overrides),
               request: Map.put(post_request(board.uri), :remote_ip, "24.48.0.1")
             )

    assert thread.flag_codes == ["us"]
    assert thread.flag_alts == ["United States"]
  end

  test "create_post applies default_user_flag when it is allowed" do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          default_user_flag: "spc",
          user_flags: %{"sau" => "Sauce", "spc" => "Space"}
        }
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.flag_codes == ["spc"]
    assert thread.flag_alts == ["Space"]
  end

  test "create_post rejects user flags outside the allowlist" do
    board =
      board_fixture(%{
        config_overrides: %{user_flag: true, user_flags: %{"sau" => "Sauce", "spc" => "Space"}}
      })

    assert {:error, :invalid_user_flag} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "user_flag" => "invalid",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post parses multiple comma-separated flags and serializes alt text" do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          multiple_flags: true,
          user_flags: %{"country" => "Country", "sau" => "Sauce", "spc" => "Space"}
        }
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "user_flag" => " sau, spc ",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.flag_codes == ["sau", "spc"]
    assert thread.flag_alts == ["Sauce", "Space"]
  end

  test "create_post de-duplicates repeated multi flags using countFlags-style normalization" do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          multiple_flags: true,
          user_flags: %{"sau" => "Sauce", "spc" => "Space"}
        }
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "user_flag" => "sau, spc, sau, spc",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.flag_codes == ["sau", "spc"]
    assert thread.flag_alts == ["Sauce", "Space"]
  end

  test "create_post rejects overlong multiple flag input" do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          multiple_flags: true,
          user_flags: %{"sau" => "Sauce", "spc" => "Space"}
        }
      })

    long_flags = String.duplicate("sau,", 76)

    assert {:error, :invalid_user_flag} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "user_flag" => long_flags,
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post auto-injects a country flag from request metadata" do
    board =
      board_fixture(%{
        config_overrides: %{
          country_flags: true,
          country_flag_data: %{"187.180.254.75" => %{code: "mx", name: "Mexico"}}
        }
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: Map.put(post_request(board.uri), :remote_ip, {187, 180, 254, 75})
             )

    assert thread.flag_codes == ["mx"]
    assert thread.flag_alts == ["Mexico"]
  end

  test "create_post skips auto country injection when no_country is enabled" do
    board =
      board_fixture(%{
        config_overrides: %{
          country_flags: true,
          allow_no_country: true,
          country_flag_data: %{"187.180.254.75" => %{code: "mx", name: "Mexico"}}
        }
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "no_country" => "1",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: Map.put(post_request(board.uri), :remote_ip, {187, 180, 254, 75})
             )

    assert thread.flag_codes == []
    assert thread.flag_alts == []
  end

  test "create_post resolves the country pseudo-flag with fallback metadata" do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          multiple_flags: true,
          user_flags: %{"country" => "Country", "sau" => "Sauce"}
        }
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "user_flag" => "country, sau",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.flag_codes == ["us", "sau"]
    assert thread.flag_alts == ["United States", "Sauce"]
  end

  test "create_post can resolve country metadata via the bundled GeoIP2 database" do
    board = board_fixture()

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "geoip body",
                 "post" => "New Topic"
               },
               config:
                 post_config(%{
                   country_flags: true,
                   geoip2_database_path: bundled_geoip_database_path()
                 }),
               request: %{
                 referer: "http://example.test/#{board.uri}/index.html",
                 remote_ip: {24, 48, 0, 1}
               }
             )

    assert thread.flag_codes == ["ca"]
    assert thread.flag_alts == ["Canada"]
  end

  test "create_post stores allowed OP tags and proxy metadata and encodes compatibility modifiers" do
    board =
      board_fixture(%{
        config_overrides: %{
          allowed_tags: %{"A" => "Anime", "M" => "Music"},
          proxy_save: true
        }
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "tag" => "A",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request:
                 post_request(board.uri)
                 |> Map.put(:forwarded_for, "203.0.113.4, 10.0.0.1<script>")
             )

    assert thread.tag == "A"
    assert thread.proxy == "203.0.113.4, 10.0.0.1"

    compat_body = Posts.compat_body(thread)
    assert compat_body =~ "<tinyboard tag>A</tinyboard>"
    assert compat_body =~ "<tinyboard proxy>203.0.113.4, 10.0.0.1</tinyboard>"
  end

  test "create_post ignores disallowed tags and reply tags" do
    board = board_fixture(%{config_overrides: %{allowed_tags: %{"A" => "Anime"}}})
    config = post_config(board.config_overrides)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "first post", "tag" => "invalid", "post" => "New Topic"},
               config: config,
               request: post_request(board.uri)
             )

    assert thread.tag == nil

    assert {:ok, reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "reply body",
                 "tag" => "A",
                 "post" => "New Reply"
               },
               config: config,
               request: post_request(board.uri)
             )

    assert reply.tag == nil
  end

  test "create_post applies wordfilters before storing post text" do
    board =
      board_fixture(%{
        config_overrides: %{wordfilters: [%{pattern: "badword", replacement: "goodword"}]}
      })

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "badword here", "subject" => "badword", "post" => "New Topic"},
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.body == "goodword here"
    assert thread.subject == "badword"
  end

  test "create_post strips combining characters when configured" do
    board = board_fixture(%{config_overrides: %{strip_combining_chars: true}})

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Cafe\u0301", "name" => "A\u0301non", "post" => "New Topic"},
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.body == "Cafe"
    assert thread.name == "Anon"
  end

  test "create_post escapes user-supplied tinyboard modifiers before compatibility encoding" do
    board = board_fixture()

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "<tinyboard flag>evil</tinyboard>",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.body == "&lt;tinyboard flag>evil&lt;/tinyboard&gt;"
    refute Posts.compat_body(thread) =~ "\n<tinyboard flag>evil</tinyboard>"
  end

  test "create_post lets authorized moderators bypass board and thread locks" do
    board = board_fixture(%{config_overrides: %{board_locked: true}})
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(board)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "mod thread", "post" => "New Topic"},
               config: post_config(board.config_overrides),
               request: %{moderator: moderator}
             )

    {:ok, _locked_thread} =
      Posts.update_thread_state(board, thread.id, %{"locked" => true},
        config: post_config(board.config_overrides)
      )

    assert {:ok, reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "mod reply",
                 "post" => "New Reply"
               },
               config: post_config(board.config_overrides),
               request: %{moderator: moderator}
             )

    assert reply.thread_id == thread.id
  end

  test "create_post enforces hidden antispam hash validation" do
    board =
      board_fixture(%{
        config_overrides: %{hidden_input_name: "hash", hidden_input_hash: "expected"}
      })

    config = post_config(board.config_overrides)

    assert {:error, :antispam} =
             Posts.create_post(
               board,
               %{"body" => "first post", "post" => "New Topic"},
               config: config,
               request: post_request(board.uri)
             )

    assert {:ok, _thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "first post", "hash" => "expected", "post" => "New Topic"},
               config: config,
               request: post_request(board.uri)
             )
  end

  test "create_post enforces simple antispam question only for OPs" do
    board =
      board_fixture(%{
        config_overrides: %{antispam_question: "2+2?", antispam_question_answer: "4"}
      })

    config = post_config(board.config_overrides)

    assert {:error, :antispam} =
             Posts.create_post(
               board,
               %{"body" => "first post", "post" => "New Topic"},
               config: config,
               request: post_request(board.uri)
             )

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "antispam_answer" => "4",
                 "post" => "New Topic"
               },
               config: config,
               request: post_request(board.uri)
             )

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "reply body",
                 "post" => "New Reply"
               },
               config: config,
               request: post_request(board.uri)
             )
  end

  test "create_post validates captcha responses across providers" do
    board =
      board_fixture(%{
        config_overrides: %{
          captcha: %{enabled: true, provider: "recaptcha", expected_response: "ok"}
        }
      })

    assert {:error, :invalid_captcha} =
             Posts.create_post(
               board,
               %{"body" => "first post", "post" => "New Topic"},
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert {:ok, _thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "g-recaptcha-response" => "ok",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post supports hosted captcha verification endpoints" do
    server = serve_json_response(~s({"success":true}))

    on_exit(fn ->
      server.stop.()
    end)

    board =
      board_fixture(%{
        config_overrides: %{
          captcha: %{
            enabled: true,
            provider: "recaptcha",
            verify_url: server.url,
            secret: "topsecret"
          }
        }
      })

    assert {:ok, _thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "g-recaptcha-response" => "remote-ok",
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post applies captcha mode only to the configured post type" do
    board =
      board_fixture(%{
        config_overrides: %{
          captcha: %{enabled: true, provider: "native", expected_response: "ok", mode: "reply"}
        }
      })

    config = post_config(board.config_overrides)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "first post", "post" => "New Topic"},
               config: config,
               request: post_request(board.uri)
             )

    assert {:error, :invalid_captcha} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "reply body",
                 "post" => "New Reply"
               },
               config: config,
               request: post_request(board.uri)
             )

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "reply body",
                 "captcha" => "ok",
                 "post" => "New Reply"
               },
               config: config,
               request: post_request(board.uri)
             )
  end

  test "create_post extracts cites and stores nntp references for existing posts" do
    board = board_fixture()
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread)

    assert {:ok, citing_post, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" =>
                   "see >>#{PublicIds.public_id(thread)} and >>#{PublicIds.public_id(reply)} and >>999999",
                 "post" => "New Reply"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert Enum.map(Posts.list_cites_for_post(citing_post, repo: Repo), & &1.target_post_id) == [
             thread.id,
             reply.id
           ]

    assert Enum.map(
             Posts.list_nntp_references_for_post(citing_post, repo: Repo),
             & &1.target_post_id
           ) == [
             thread.id,
             reply.id
           ]
  end

  test "create_post generates and stores tripcodes from poster names" do
    board = board_fixture()

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"name" => "Anon#secret", "body" => "first post", "post" => "New Topic"},
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert thread.name == "Anon"
    assert String.starts_with?(thread.tripcode, "!")
    assert String.length(thread.tripcode) == 11
    assert Posts.compat_body(thread) =~ "<tinyboard trip>#{thread.tripcode}</tinyboard>"
  end

  test "create_post enforces required OP files and upload validation" do
    board = board_fixture(%{config_overrides: %{force_image_op: true}})
    config = post_config(board.config_overrides)

    assert {:error, :file_required} =
             Posts.create_post(board, %{"body" => "first post", "post" => "New Topic"},
               config: config,
               request: post_request(board.uri)
             )

    assert {:error, :invalid_file_type} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => upload_fixture("bad.txt", "bad"),
                 "post" => "New Topic"
               },
               config: config,
               request: post_request(board.uri)
             )

    assert {:error, :invalid_image} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "file" => raw_upload_fixture("fake.png", "not-an-image"),
                 "post" => "New Topic"
               },
               config: config,
               request: post_request(board.uri)
             )

    oversized_board = board_fixture(%{config_overrides: %{max_filesize: 1}})

    assert {:error, :file_too_large} =
             Posts.create_post(
               oversized_board,
               %{
                 "body" => "first post",
                 "file" => upload_fixture("big.png", "12345"),
                 "post" => "New Topic"
               },
               config: post_config(oversized_board.config_overrides),
               request: post_request(oversized_board.uri)
             )

    oversized_dimensions_board =
      board_fixture(%{config_overrides: %{max_image_width: 8, max_image_height: 8}})

    assert {:error, :image_too_large} =
             Posts.create_post(
               oversized_dimensions_board,
               %{
                 "body" => "first post",
                 "file" => upload_fixture("wide.png", geometry: "12x9"),
                 "post" => "New Topic"
               },
               config: post_config(oversized_dimensions_board.config_overrides),
               request: post_request(oversized_dimensions_board.uri)
             )
  end

  test "create_post enforces split multi-file size limits" do
    board = board_fixture(%{config_overrides: %{max_filesize: 150, multiimage_method: "split"}})

    assert {:error, :file_too_large} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "files" => [
                   upload_fixture("first.png", content: "first", geometry: "64x64"),
                   upload_fixture("second.png", content: "second", geometry: "64x64")
                 ],
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post allows multi-file posts when max_filesize uses each mode" do
    board = board_fixture(%{config_overrides: %{max_filesize: 550, multiimage_method: "each"}})

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "first post",
                 "files" => [
                   upload_fixture("first.png", content: "first", geometry: "64x64"),
                   upload_fixture("second.png", content: "second", geometry: "64x64")
                 ],
                 "post" => "New Topic"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert length(thread.extra_files) == 1
  end

  test "create_post enforces reply hard limits" do
    board = board_fixture(%{config_overrides: %{reply_hard_limit: 1}})
    thread = thread_fixture(board)

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "first reply",
                 "post" => "New Reply"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert {:error, :reply_hard_limit} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "second reply",
                 "post" => "New Reply"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post enforces image hard limits for file replies" do
    board = board_fixture(%{config_overrides: %{image_hard_limit: 1}})
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "file" => upload_fixture("thread.png", "thread"),
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )

    assert {:error, :image_hard_limit} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply body",
                 "file" => upload_fixture("reply.png", "reply"),
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Text-only reply",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )
  end

  test "create_post rejects duplicate files globally when configured" do
    board = board_fixture(%{config_overrides: %{duplicate_file_mode: "global"}})
    config = post_config(board.config_overrides)
    request = post_request(board.uri)
    upload = upload_fixture("first.png", "same-bytes")
    duplicate_upload = duplicate_upload_fixture(upload, "second.png")

    assert {:ok, _thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )

    assert {:error, :duplicate_file} =
             Posts.create_post(
               board,
               %{
                 "body" => "Second body",
                 "file" => duplicate_upload,
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )
  end

  test "create_post rejects duplicate files within a thread when configured" do
    board = board_fixture(%{config_overrides: %{duplicate_file_mode: "thread"}})
    config = post_config(board.config_overrides)
    request = post_request(board.uri)
    upload = upload_fixture("first.png", "thread-bytes")
    reply_upload = duplicate_upload_fixture(upload, "reply.png")
    other_upload = duplicate_upload_fixture(upload, "other.png")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "file" => upload,
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )

    assert {:error, :duplicate_file} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply body",
                 "file" => reply_upload,
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    other_board = board_fixture(%{config_overrides: %{duplicate_file_mode: "thread"}})

    assert {:ok, _other_thread, _meta} =
             Posts.create_post(
               other_board,
               %{
                 "body" => "Other body",
                 "file" => other_upload,
                 "post" => "New Topic"
               },
               config: post_config(other_board.config_overrides),
               request: post_request(other_board.uri)
             )
  end

  test "create_post rejects replies to locked threads" do
    board = board_fixture()
    thread = thread_fixture(board)

    Repo.update_all(
      from(post in Eirinchan.Posts.Post, where: post.id == ^thread.id),
      set: [locked: true]
    )

    assert {:error, :thread_locked} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply body",
                 "post" => "New Reply"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )
  end

  test "create_post rejects dnsbl-listed IPs" do
    board = board_fixture()

    config =
      post_config(%{
        dnsbl: [["rbl.example", 4]],
        error: %{dnsbl: "Your IP address is listed in %s."}
      })

    resolver = fn
      "9.113.0.203.rbl.example" -> "127.0.0.4"
      _ -> nil
    end

    assert {:error, :dnsbl} =
             Posts.create_post(
               board,
               %{"body" => "dnsbl blocked", "post" => "New Topic"},
               config: config,
               request: %{
                 referer: "http://example.test/#{board.uri}/index.html",
                 remote_ip: {203, 0, 113, 9},
                 dnsbl_resolver: resolver
               }
             )
  end

  test "create_post skips dnsbl when disabled" do
    board = board_fixture()

    config =
      post_config(%{
        use_dnsbl: false,
        dnsbl: [["rbl.example", 4]],
        error: %{dnsbl: "Your IP address is listed in %s."}
      })

    resolver = fn
      "9.113.0.203.rbl.example" -> "127.0.0.4"
      _ -> nil
    end

    assert {:ok, _thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{"body" => "dnsbl allowed", "post" => "New Topic"},
               config: config,
               request: %{
                 referer: "http://example.test/#{board.uri}/index.html",
                 remote_ip: {203, 0, 113, 9},
                 dnsbl_resolver: resolver
               }
             )
  end

  test "create_post rejects IPs outside the ipaccess allowlist" do
    board = board_fixture()

    access_file =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-ipaccess-#{System.unique_integer([:positive])}.conf"
      )

    File.write!(access_file, "198.51.100.0/24\n")

    config =
      post_config(%{
        ipaccess: true,
        ipaccess_file: access_file
      })

    assert {:error, :ipaccess} =
             Posts.create_post(
               board,
               %{"body" => "blocked by ipaccess", "post" => "New Topic"},
               config: config,
               request: %{
                 referer: "http://example.test/#{board.uri}/index.html",
                 remote_ip: {203, 0, 113, 9}
               }
             )
  end

  test "create_post bypasses ipaccess when the flag threshold is met" do
    board = board_fixture()

    access_file =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-ipaccess-bypass-#{System.unique_integer([:positive])}.conf"
      )

    File.write!(access_file, "198.51.100.0/24\n")

    config =
      post_config(%{
        ipaccess: true,
        ipaccess_file: access_file,
        ip_nulling_flags: 8
      })

    assert {:ok, _thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "allowed by flag threshold",
                 "post" => "New Topic",
                 "user_flag" => "country,mokou"
               },
               config: config,
               request: %{
                 referer: "http://example.test/#{board.uri}/index.html",
                 remote_ip: {203, 0, 113, 9}
               }
             )
  end

  test "create_post bypasses dnsbl when the flag threshold is met" do
    board = board_fixture()

    config =
      post_config(%{
        ip_nulling_flags: 8,
        dnsbl: [["rbl.example", 4]],
        error: %{dnsbl: "Your IP address is listed in %s."}
      })

    resolver = fn
      "9.113.0.203.rbl.example" -> "127.0.0.4"
      _ -> nil
    end

    assert {:ok, _thread, %{noko: false}} =
             Posts.create_post(
               board,
               %{
                 "body" => "dnsbl bypassed",
                 "post" => "New Topic",
                 "user_flag" => "country,mokou"
               },
               config: config,
               request: %{
                 referer: "http://example.test/#{board.uri}/index.html",
                 remote_ip: {203, 0, 113, 9},
                 dnsbl_resolver: resolver
               }
             )
  end

  test "reply bumping reorders threads unless the reply is sage" do
    board = board_fixture()
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, older_thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Older", "subject" => "Older", "post" => "New Topic"},
               config: config,
               request: request
             )

    Process.sleep(1000)

    assert {:ok, newer_thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Newer", "subject" => "Newer", "post" => "New Topic"},
               config: config,
               request: request
             )

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(older_thread.id),
                 "body" => "Bumping reply",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, page_after_bump} = Posts.list_threads_page(board, 1, config: config)
    assert hd(page_after_bump.threads).thread.id == older_thread.id

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(newer_thread.id),
                 "body" => "Sage reply",
                 "email" => "sage",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, page_after_sage} = Posts.list_threads_page(board, 1, config: config)
    assert hd(page_after_sage.threads).thread.id == older_thread.id
  end

  test "find_thread_page tracks bump ordering and slug thread ids" do
    board = board_fixture(%{config_overrides: %{threads_per_page: 1, slugify: true}})
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, older_thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Older body", "subject" => "Older subject", "post" => "New Topic"},
               config: config,
               request: request
             )

    assert {:ok, newer_thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Newer body", "subject" => "Newer subject", "post" => "New Topic"},
               config: config,
               request: request
             )

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(older_thread.id),
                 "body" => "Bumping reply",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, 1} = Posts.find_thread_page(board, older_thread.id, config: config)

    assert {:ok, 2} =
             Posts.find_thread_page(board, "#{newer_thread.id}-newer-subject.html", config: config)

    assert {:ok, [thread | _]} =
             Posts.get_thread(board, "#{older_thread.id}-older-subject.html", config: config)

    assert thread.id == older_thread.id
  end

  test "update_thread_state applies cycle and bumplock behavior to future replies" do
    board = board_fixture(%{config_overrides: %{cycle_limit: 1, threads_per_page: 1}})
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Opening body", "subject" => "Opening", "post" => "New Topic"},
               config: config,
               request: request
             )

    initial_bump_at = thread.bump_at

    assert {:ok, updated_thread} =
             Posts.update_thread_state(
               board,
               thread.id,
               %{"cycle" => "true", "sage" => "true"},
               config: config
             )

    assert updated_thread.cycle
    assert updated_thread.sage

    assert {:ok, first_reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "First reply",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, second_reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Second reply",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, [reloaded_thread | replies]} = Posts.get_thread(board, thread.id, config: config)
    assert reloaded_thread.bump_at == initial_bump_at
    assert Enum.map(replies, & &1.id) == [second_reply.id]
    refute Enum.any?(replies, &(&1.id == first_reply.id))
  end

  test "delete_post removes replies when the password matches" do
    board = board_fixture()
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "subject" => "Opening",
                 "password" => "threadpw",
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )

    assert {:ok, reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply body",
                 "password" => "replypw",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:error, :invalid_password} =
             Posts.delete_post(board, PublicIds.public_id(reply), "wrong", config: config)

    assert {:ok, %{deleted_post_id: deleted_post_id, thread_id: thread_id, thread_deleted: false}} =
             Posts.delete_post(board, PublicIds.public_id(reply), "replypw", config: config)

    assert deleted_post_id == PublicIds.public_id(reply)
    assert thread_id == PublicIds.public_id(thread)
    assert {:ok, [reloaded_thread]} = Posts.get_thread(board, PublicIds.public_id(thread), config: config)
    assert reloaded_thread.id == thread.id
  end

  test "delete_post removes threads and cascades replies when the password matches" do
    board = board_fixture()
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "subject" => "Opening",
                 "password" => "threadpw",
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply body",
                 "password" => "replypw",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, %{deleted_post_id: deleted_post_id, thread_id: thread_id, thread_deleted: true}} =
             Posts.delete_post(board, PublicIds.public_id(thread), "threadpw", config: config)

    assert deleted_post_id == PublicIds.public_id(thread)
    assert thread_id == PublicIds.public_id(thread)
    assert {:error, :not_found} = Posts.get_thread(board, PublicIds.public_id(thread), config: config)
    assert Posts.list_threads(board, config: config) == []
  end

  test "list_threads_page returns previews, omitted counts, and page metadata" do
    board = board_fixture(%{config_overrides: %{threads_per_page: 1, threads_preview: 1}})
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, older_thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Older body", "subject" => "Older", "post" => "New Topic"},
               config: config,
               request: request
             )

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(older_thread.id),
                 "body" => "Reply one",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(older_thread.id),
                 "body" => "Reply two",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, _newer_thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Newer body", "subject" => "Newer", "post" => "New Topic"},
               config: config,
               request: request
             )

    assert {:ok, first_page} = Posts.list_threads_page(board, 1, config: config)
    assert first_page.page == 1
    assert first_page.total_pages == 2
    assert Enum.map(first_page.pages, & &1.num) == [1, 2]
    assert hd(first_page.threads).thread.subject == "Newer"

    assert {:ok, second_page} = Posts.list_threads_page(board, 2, config: config)
    summary = hd(second_page.threads)
    assert summary.thread.id == older_thread.id
    assert summary.reply_count == 2
    assert summary.omitted_posts == 1
    assert Enum.map(summary.replies, & &1.body) == ["Reply two"]
  end

  test "list_threads_page uses sticky preview count for sticky threads" do
    board =
      board_fixture(%{
        config_overrides: %{threads_per_page: 1, threads_preview: 5, threads_preview_sticky: 2}
      })

    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Sticky body", "subject" => "Sticky", "post" => "New Topic"},
               config: config,
               request: request
             )

    Repo.update_all(from(post in Post, where: post.id == ^thread.id), set: [sticky: true])

    for body <- ["Reply one", "Reply two", "Reply three"] do
      assert {:ok, _reply, _meta} =
               Posts.create_post(
                 board,
                 %{
                   "thread" => Integer.to_string(PublicIds.public_id(thread)),
                   "body" => body,
                   "post" => "New Reply"
                 },
                 config: config,
                 request: request
               )
    end

    assert {:ok, page_data} = Posts.list_threads_page(board, 1, config: config)
    summary = hd(page_data.threads)

    assert summary.thread.id == thread.id
    assert summary.reply_count == 3
    assert summary.omitted_posts == 1
    assert Enum.map(summary.replies, & &1.body) == ["Reply two", "Reply three"]
  end

  test "list_threads_page orders equal timestamps by newest id" do
    board = board_fixture()
    config = post_config(board.config_overrides)

    older_thread = thread_fixture(board, %{body: "older"})
    newer_thread = thread_fixture(board, %{body: "newer"})
    shared_time = ~U[2026-03-10 18:20:00Z]

    Repo.update_all(
      from(post in Post, where: post.id in ^[older_thread.id, newer_thread.id]),
      set: [inserted_at: shared_time, bump_at: shared_time]
    )

    assert {:ok, page_data} = Posts.list_threads_page(board, 1, config: config)

    assert Enum.at(page_data.threads, 0).thread.id == newer_thread.id
    assert Enum.at(page_data.threads, 1).thread.id == older_thread.id
  end

  test "thread views count image replies and omitted images" do
    board = board_fixture(%{config_overrides: %{threads_preview: 1}})
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "file" => upload_fixture("op.png", "op"),
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )

    assert {:ok, _reply_one, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply one",
                 "file" => upload_fixture("reply1.png", "reply-one"),
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, _reply_two, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply two",
                 "file" => upload_fixture("reply2.png", "reply-two"),
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, page_data} = Posts.list_threads_page(board, 1, config: config)
    summary = hd(page_data.threads)

    assert summary.image_count == 3
    assert summary.omitted_posts == 1
    assert summary.omitted_images == 1

    assert {:ok, thread_view} = Posts.get_thread_view(board, thread.id, config: config)
    assert thread_view.image_count == 3
  end

  test "thread view supports last x posts truncation" do
    board =
      board_fixture(%{
        config_overrides: %{noko50_count: 2, noko50_min: 3}
      })

    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Opening body", "subject" => "Thread", "post" => "New Topic"},
               config: config,
               request: request
             )

    for body <- ["Reply one", "Reply two", "Reply three"] do
      assert {:ok, _reply, _meta} =
               Posts.create_post(
                 board,
                 %{
                   "thread" => Integer.to_string(PublicIds.public_id(thread)),
                   "body" => body,
                   "post" => "New Reply"
                 },
                 config: config,
                 request: request
               )
    end

    assert {:ok, summary} = Posts.get_thread_view(board, thread.id, config: config)
    assert summary.has_noko50
    refute summary.is_noko50
    assert summary.reply_count == 3
    assert Enum.map(summary.replies, & &1.body) == ["Reply one", "Reply two", "Reply three"]

    assert {:ok, last_summary} =
             Posts.get_thread_view(board, thread.id, config: config, last_posts: true)

    assert last_summary.has_noko50
    assert last_summary.is_noko50
    assert last_summary.last_count == 2
    assert last_summary.omitted_posts == 1
    assert Enum.map(last_summary.replies, & &1.body) == ["Reply two", "Reply three"]
  end

  test "delete_post removes uploaded files for replies and threads" do
    board = board_fixture()
    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "password" => "threadpw",
                 "file" => upload_fixture("thread.png", "thread"),
                 "post" => "New Topic"
               },
               config: config,
               request: request
             )

    assert {:ok, reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply body",
                 "password" => "replypw",
                 "file" => upload_fixture("reply.png", "reply"),
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert File.exists?(Eirinchan.Uploads.filesystem_path(reply.file_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(reply.thumb_path))

    assert {:ok, %{thread_deleted: false}} =
             Posts.delete_post(board, PublicIds.public_id(reply), "replypw", config: config)

    refute File.exists?(Eirinchan.Uploads.filesystem_path(reply.file_path))
    refute File.exists?(Eirinchan.Uploads.filesystem_path(reply.thumb_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.thumb_path))

    assert {:ok, %{thread_deleted: true}} =
             Posts.delete_post(board, PublicIds.public_id(thread), "threadpw", config: config)

    refute File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
    refute File.exists?(Eirinchan.Uploads.filesystem_path(thread.thumb_path))
  end

  test "update_post edits text and refreshes citations" do
    board = board_fixture()
    config = post_config(board.config_overrides)
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread, %{body: "Before"})

    assert {:ok, updated_reply} =
             Posts.update_post(
               board,
               reply.id,
               %{"body" => "After >>#{PublicIds.public_id(thread)}"},
               config: config
             )

    assert updated_reply.body == "After >>#{PublicIds.public_id(thread)}"

    assert Enum.map(Posts.list_cites_for_post(updated_reply, repo: Repo), & &1.target_post_id) ==
             [thread.id]
  end

  test "moderate_delete_post removes posts without a password" do
    board = board_fixture()
    config = post_config(board.config_overrides)
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread, %{password: "userpw"})

    assert {:ok, %{deleted_post_id: deleted_post_id, thread_deleted: false}} =
             Posts.moderate_delete_post(board, reply.id, config: config)

    assert deleted_post_id == PublicIds.public_id(reply)
    assert {:ok, [reloaded_thread]} = Posts.get_thread(board, thread.id, config: config)
    assert reloaded_thread.id == thread.id
  end

  test "delete_post_files removes primary and extra files but leaves the post" do
    board = board_fixture()
    config = post_config(board.config_overrides)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "files" => [
                   upload_fixture("first.png", "first"),
                   upload_fixture("second.gif", "second")
                 ],
                 "post" => "New Topic"
               },
               config: config,
               request: post_request(board.uri)
             )

    [extra] = thread.extra_files

    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(extra.file_path))

    assert {:ok, updated_thread} = Posts.delete_post_files(board, thread.id, config: config)

    assert updated_thread.file_path == "deleted"
    assert updated_thread.thumb_path == nil
    assert Enum.map(updated_thread.extra_files, & &1.file_path) == ["deleted"]
    refute File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
    refute File.exists?(Eirinchan.Uploads.filesystem_path(extra.file_path))
  end

  test "delete_post_file removes a targeted extra file and preserves the rest" do
    board = board_fixture()
    config = post_config(board.config_overrides)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "files" => [
                   upload_fixture("first.png", "first"),
                   upload_fixture("second.gif", "second")
                 ],
                 "post" => "New Topic"
               },
               config: config,
               request: post_request(board.uri)
             )

    [extra] = thread.extra_files

    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(extra.file_path))

    assert {:ok, updated_thread} = Posts.delete_post_file(board, thread.id, 1, config: config)

    assert updated_thread.file_path == thread.file_path
    assert updated_thread.thumb_path == thread.thumb_path
    assert Enum.map(updated_thread.extra_files, & &1.file_path) == ["deleted"]
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
    refute File.exists?(Eirinchan.Uploads.filesystem_path(extra.file_path))
  end

  test "spoilerize_post_files marks files as spoilers and rewrites thumbs" do
    board = board_fixture()
    config = post_config(board.config_overrides)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "files" => [
                   upload_fixture("first.png", "first"),
                   upload_fixture("second.gif", "second")
                 ],
                 "post" => "New Topic"
               },
               config: config,
               request: post_request(board.uri)
             )

    thumb_before = File.read!(Eirinchan.Uploads.filesystem_path(thread.thumb_path))

    assert {:ok, spoilered_thread} = Posts.spoilerize_post_files(board, thread.id, config: config)

    assert spoilered_thread.spoiler
    assert Enum.all?(spoilered_thread.extra_files, & &1.spoiler)
    refute File.read!(Eirinchan.Uploads.filesystem_path(thread.thumb_path)) == thumb_before
  end

  test "spoilerize_post_file marks only the targeted extra file as spoiler" do
    board = board_fixture()
    config = post_config(board.config_overrides)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "files" => [
                   upload_fixture("first.png", "first"),
                   upload_fixture("second.gif", "second")
                 ],
                 "post" => "New Topic"
               },
               config: config,
               request: post_request(board.uri)
             )

    assert {:ok, spoilered_thread} =
             Posts.spoilerize_post_file(board, thread.id, 1, config: config)

    refute spoilered_thread.spoiler
    assert [%{spoiler: true}] = spoilered_thread.extra_files
  end

  test "create_post records flood entries and rejects rapid repeated posts from the same ip" do
    board =
      board_fixture(%{config_overrides: %{flood_time: 60, flood_time_ip: 0, flood_time_same: 0}})

    config = post_config(board.config_overrides)

    request = %{
      referer: "http://example.test/#{board.uri}/index.html",
      remote_ip: {203, 0, 113, 11}
    }

    assert {:ok, _thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "first body", "post" => "New Topic"},
               config: config,
               request: request,
               repo: Repo
             )

    assert [%{ip_subnet: "203.0.113.11"}] =
             Antispam.list_flood_entries("203.0.113.11", repo: Repo)

    assert {:error, :antispam} =
             Posts.create_post(
               board,
               %{"body" => "second body", "post" => "New Topic"},
               config: config,
               request: request,
               repo: Repo
             )
  end

  test "create_post rejects repeated bodies within the same-ip repeat window" do
    board =
      board_fixture(%{config_overrides: %{flood_time: 0, flood_time_ip: 60, flood_time_same: 0}})

    config = post_config(board.config_overrides)

    request = %{
      referer: "http://example.test/#{board.uri}/index.html",
      remote_ip: {203, 0, 113, 12}
    }

    assert {:ok, _thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "same body", "post" => "New Topic"},
               config: config,
               request: request,
               repo: Repo
             )

    assert {:error, :antispam} =
             Posts.create_post(
               board,
               %{"body" => "same body", "post" => "New Topic"},
               config: config,
               request: request,
               repo: Repo
             )
  end

  test "create_post rejects repeated bodies across different ips within the flood same window" do
    board =
      board_fixture(%{config_overrides: %{flood_time: 0, flood_time_ip: 0, flood_time_same: 60}})

    config = post_config(board.config_overrides)

    assert {:ok, _thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "same body", "post" => "New Topic"},
               config: config,
               request: %{
                 referer: "http://example.test/#{board.uri}/index.html",
                 remote_ip: {203, 0, 113, 21}
               },
               repo: Repo
             )

    assert {:error, :antispam} =
             Posts.create_post(
               board,
               %{"body" => "same body", "post" => "New Topic"},
               config: config,
               request: %{
                 referer: "http://example.test/#{board.uri}/index.html",
                 remote_ip: {203, 0, 113, 22}
               },
               repo: Repo
             )
  end

  test "create_post rejects too many links" do
    board = board_fixture()
    config = post_config(board.config_overrides)

    body =
      1..21
      |> Enum.map_join("\n", fn index -> "https://example.test/#{index}" end)

    assert {:error, :toomanylinks} =
             Posts.create_post(
               board,
               %{"body" => body, "post" => "New Topic"},
               config: config,
               request: post_request(board.uri),
               repo: Repo
             )
  end

  test "create_post enforces max threads per hour" do
    board =
      board_fixture(%{
        config_overrides: %{
          max_threads_per_hour: 1,
          flood_time: 0,
          flood_time_ip: 0,
          flood_time_same: 0
        }
      })

    config = post_config(board.config_overrides)
    request = post_request(board.uri)

    assert {:ok, _thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "first thread", "post" => "New Topic"},
               config: config,
               request: request,
               repo: Repo
             )

    assert {:error, :too_many_threads} =
             Posts.create_post(
               board,
               %{"body" => "second thread", "post" => "New Topic"},
               config: config,
               request: request,
               repo: Repo
             )
  end

  test "anti_bump_flood keeps thread bump time at the latest non-sage reply" do
    board =
      board_fixture(%{
        config_overrides: %{
          anti_bump_flood: true,
          flood_time: 0,
          flood_time_ip: 0,
          flood_time_same: 0
        }
      })

    config = post_config(board.config_overrides)
    request = Map.put(post_request(board.uri), :remote_ip, {203, 0, 113, 34})

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "thread", "post" => "New Topic"},
               config: config,
               request: request,
               repo: Repo
             )

    assert {:ok, _reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "bump",
                 "post" => "Reply"
               },
               config: config,
               request: request,
               repo: Repo
             )

    bumped_thread = Repo.get!(Post, thread.id)
    first_bump_at = bumped_thread.bump_at

    assert {:ok, _sage_reply, _meta} =
             Posts.create_post(
               board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "sage",
                 "email" => "sage",
                 "post" => "Reply"
               },
               config: config,
               request: request,
               repo: Repo
             )

    assert Repo.get!(Post, thread.id).bump_at == first_bump_at
  end

  test "anti_bump_flood restores thread ordering after deleting the latest bumping reply" do
    board =
      board_fixture(%{
        config_overrides: %{
          anti_bump_flood: true,
          flood_time: 0,
          flood_time_ip: 0,
          flood_time_same: 0
        }
      })

    config = post_config(board.config_overrides)
    request = Map.put(post_request(board.uri), :remote_ip, {203, 0, 113, 35})

    assert {:ok, older_thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Older", "subject" => "Older", "post" => "New Topic"},
               config: config,
               request: request,
               repo: Repo
             )

    Process.sleep(1000)

    assert {:ok, newer_thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Newer", "subject" => "Newer", "post" => "New Topic"},
               config: config,
               request: request,
               repo: Repo
             )

    Process.sleep(1000)

    assert {:ok, bump_reply, _meta} =
             Posts.create_post(
               board,
                %{
                 "thread" => Integer.to_string(PublicIds.public_id(older_thread)),
                 "body" => "Bumping reply",
                 "password" => "replypw",
                 "post" => "New Reply"
               },
               config: config,
               request: request,
               repo: Repo
             )

    assert {:ok, page_after_bump} = Posts.list_threads_page(board, 1, config: config, repo: Repo)
    assert hd(page_after_bump.threads).thread.id == older_thread.id

    assert {:ok, %{deleted_post_id: deleted_post_id, thread_deleted: false}} =
             Posts.delete_post(board, PublicIds.public_id(bump_reply), "replypw", config: config, repo: Repo)

    assert deleted_post_id == PublicIds.public_id(bump_reply)

    assert {:ok, page_after_delete} =
             Posts.list_threads_page(board, 1, config: config, repo: Repo)

    assert hd(page_after_delete.threads).thread.id == newer_thread.id
  end

  test "move_thread moves posts, files, and rebuilds both boards" do
    source_board = board_fixture()
    target_board = board_fixture()
    source_config = post_config(source_board.config_overrides)
    target_config = post_config(target_board.config_overrides)

    assert {:ok, thread, _meta} =
             Posts.create_post(
               source_board,
               %{
                 "body" => "Thread body",
                 "file" => upload_fixture("thread.png", geometry: "32x32"),
                 "post" => "New Topic"
               },
               config: source_config,
               request: post_request(source_board.uri)
             )

    assert {:ok, reply, _meta} =
             Posts.create_post(
               source_board,
               %{
                 "thread" => Integer.to_string(PublicIds.public_id(thread)),
                 "body" => "Reply body",
                 "file" => upload_fixture("reply.png", geometry: "32x32"),
                 "post" => "New Reply"
               },
               config: source_config,
               request: post_request(source_board.uri)
             )

    old_thread_file = thread.file_path
    old_reply_file = reply.file_path

    source_thread_output =
      Path.join([Build.board_root(), source_board.uri, "res", "#{PublicIds.public_id(thread)}.html"])

    assert {:ok, moved_thread} =
             Posts.move_thread(
               source_board,
               thread.id,
               target_board,
               source_config: source_config,
               target_config: target_config
             )

    target_thread_output =
      Path.join([Build.board_root(), target_board.uri, "res", "#{PublicIds.public_id(moved_thread)}.html"])

    assert moved_thread.board_id == target_board.id
    assert moved_thread.file_path =~ ~r|^/#{target_board.uri}/src/\d+\.png$|
    refute File.exists?(Eirinchan.Uploads.filesystem_path(old_thread_file))
    refute File.exists?(Eirinchan.Uploads.filesystem_path(old_reply_file))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(moved_thread.file_path))
    assert File.exists?(target_thread_output)
    refute File.exists?(source_thread_output)
    assert {:error, :not_found} = Posts.get_thread(source_board, PublicIds.public_id(thread))

    assert {:ok, [reloaded_thread, moved_reply]} = Posts.get_thread(target_board, PublicIds.public_id(moved_thread))
    assert reloaded_thread.board_id == target_board.id
    assert moved_reply.board_id == target_board.id
    assert moved_reply.thread_id == thread.id
    assert moved_reply.file_path =~ ~r|^/#{target_board.uri}/src/\d+\.png$|
  end

  test "move_reply moves a reply between threads and boards" do
    source_board = board_fixture()
    target_board = board_fixture()
    source_config = post_config(source_board.config_overrides)
    target_config = post_config(target_board.config_overrides)
    source_thread = thread_fixture(source_board)
    target_thread = thread_fixture(target_board)

    assert {:ok, reply, _meta} =
             Posts.create_post(
               source_board,
                %{
                 "thread" => Integer.to_string(PublicIds.public_id(source_thread)),
                 "body" => "Movable reply",
                 "file" => upload_fixture("move-reply.png", geometry: "32x32"),
                 "post" => "New Reply"
               },
               config: source_config,
               request: post_request(source_board.uri)
             )

    old_file = reply.file_path

    assert {:ok, moved_reply} =
             Posts.move_reply(
               source_board,
               reply.id,
               target_board,
               PublicIds.public_id(target_thread),
               source_config: source_config,
               target_config: target_config
             )

    assert moved_reply.board_id == target_board.id
    assert moved_reply.thread_id == target_thread.id
    assert moved_reply.file_path =~ ~r|^/#{target_board.uri}/src/\d+\.png$|
    refute File.exists?(Eirinchan.Uploads.filesystem_path(old_file))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(moved_reply.file_path))

    assert {:ok, [reloaded_source_thread]} = Posts.get_thread(source_board, PublicIds.public_id(source_thread))
    assert reloaded_source_thread.id == source_thread.id

    assert {:ok, [_target_thread, moved_reply_from_target]} =
             Posts.get_thread(target_board, PublicIds.public_id(target_thread))

    assert moved_reply_from_target.id == reply.id

    assert File.read!(
             Path.join([Build.board_root(), target_board.uri, "res", "#{PublicIds.public_id(target_thread)}.html"])
           ) =~
             "Movable reply"
  end
end
