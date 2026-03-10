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
  alias Eirinchan.Posts
  alias Eirinchan.Posts.Post
  alias Eirinchan.Runtime.Config

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
                 "thread" => Integer.to_string(thread.id),
                 "body" => "reply body",
                 "post" => "New Reply"
               },
               config: post_config(board.config_overrides),
               request: post_request(board.uri)
             )

    assert reply.thread_id == thread.id
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
                 "resto" => Integer.to_string(thread.id),
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
    assert thread.file_path =~ ~r|^/#{board.uri}/src/\d+-#{thread.id}\.png$|
    assert thread.thumb_path =~ ~r|^/#{board.uri}/thumb/\d+-#{thread.id}s\.png$|
    assert thread.file_type == "image/png"
    assert is_binary(thread.file_md5)
    assert thread.image_width == 16
    assert thread.image_height == 16

    stored_path = Eirinchan.Uploads.filesystem_path(thread.file_path)
    assert thread.file_size == File.stat!(stored_path).size

    assert File.exists?(stored_path)

    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.thumb_path))
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
    assert thread.file_path =~ ~r|^/#{board.uri}/src/\d+-#{thread.id}\.txt$|
    assert thread.thumb_path =~ ~r|^/#{board.uri}/thumb/\d+-#{thread.id}s\.png$|
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
                 "thread" => Integer.to_string(thread.id),
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
    assert extra.file_path =~ ~r|^/#{board.uri}/src/\d+-#{thread.id}-1\.gif$|
    assert extra.thumb_path =~ ~r|^/#{board.uri}/thumb/\d+-#{thread.id}-1s\.png$|
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
                 "thread" => Integer.to_string(thread.id),
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

  test "create_post canonicalizes and truncates stored filenames" do
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

    assert thread.file_name == "a_very_long_.png"
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

    assert {:error, :not_found} = Posts.get_post(board, old_thread.id)
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

    assert {:ok, _thread} = Posts.get_post(board, old_thread.id)
  end

  test "create_post fetches remote uploads when url uploads are enabled" do
    board = board_fixture(%{config_overrides: %{upload_by_url_enabled: true}})
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

    refute Repo.exists?(from post in Post, where: post.board_id == ^board.id)
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
                 "thread" => Integer.to_string(thread.id),
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
    assert thread.subject == "goodword"
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
                 "body" => "see >>#{thread.id} and >>#{reply.id} and >>999999",
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
                 "body" => "Reply body",
                 "password" => "replypw",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:error, :invalid_password} =
             Posts.delete_post(board, reply.id, "wrong", config: config)

    assert {:ok, %{deleted_post_id: deleted_post_id, thread_id: thread_id, thread_deleted: false}} =
             Posts.delete_post(board, reply.id, "replypw", config: config)

    assert deleted_post_id == reply.id
    assert thread_id == thread.id
    assert {:ok, [reloaded_thread]} = Posts.get_thread(board, thread.id, config: config)
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
                 "thread" => Integer.to_string(thread.id),
                 "body" => "Reply body",
                 "password" => "replypw",
                 "post" => "New Reply"
               },
               config: config,
               request: request
             )

    assert {:ok, %{deleted_post_id: deleted_post_id, thread_id: thread_id, thread_deleted: true}} =
             Posts.delete_post(board, thread.id, "threadpw", config: config)

    assert deleted_post_id == thread.id
    assert thread_id == thread.id
    assert {:error, :not_found} = Posts.get_thread(board, thread.id, config: config)
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
                 "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
                   "thread" => Integer.to_string(thread.id),
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
                 "thread" => Integer.to_string(thread.id),
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
             Posts.delete_post(board, reply.id, "replypw", config: config)

    refute File.exists?(Eirinchan.Uploads.filesystem_path(reply.file_path))
    refute File.exists?(Eirinchan.Uploads.filesystem_path(reply.thumb_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.file_path))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(thread.thumb_path))

    assert {:ok, %{thread_deleted: true}} =
             Posts.delete_post(board, thread.id, "threadpw", config: config)

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
               %{"body" => "After >>#{thread.id}"},
               config: config
             )

    assert updated_reply.body == "After >>#{thread.id}"

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

    assert deleted_post_id == reply.id
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

    assert updated_thread.file_path == nil
    assert updated_thread.thumb_path == nil
    assert updated_thread.extra_files == []
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
    assert updated_thread.extra_files == []
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
    board = board_fixture(%{config_overrides: %{flood_time_ip: 60}})
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

  test "create_post rejects repeated bodies within the flood repeat window" do
    board = board_fixture(%{config_overrides: %{flood_time_same: 60}})
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
                 "thread" => Integer.to_string(thread.id),
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
      Path.join([Build.board_root(), source_board.uri, "res", "#{thread.id}.html"])

    target_thread_output =
      Path.join([Build.board_root(), target_board.uri, "res", "#{thread.id}.html"])

    assert {:ok, moved_thread} =
             Posts.move_thread(
               source_board,
               thread.id,
               target_board,
               source_config: source_config,
               target_config: target_config
             )

    assert moved_thread.board_id == target_board.id
    assert moved_thread.file_path =~ ~r|^/#{target_board.uri}/src/\d+-#{thread.id}\.png$|
    refute File.exists?(Eirinchan.Uploads.filesystem_path(old_thread_file))
    refute File.exists?(Eirinchan.Uploads.filesystem_path(old_reply_file))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(moved_thread.file_path))
    assert File.exists?(target_thread_output)
    refute File.exists?(source_thread_output)
    assert {:error, :not_found} = Posts.get_thread(source_board, thread.id)

    assert {:ok, [reloaded_thread, moved_reply]} = Posts.get_thread(target_board, thread.id)
    assert reloaded_thread.board_id == target_board.id
    assert moved_reply.board_id == target_board.id
    assert moved_reply.thread_id == thread.id
    assert moved_reply.file_path =~ ~r|^/#{target_board.uri}/src/\d+-#{reply.id}\.png$|
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
                 "thread" => Integer.to_string(source_thread.id),
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
               target_thread.id,
               source_config: source_config,
               target_config: target_config
             )

    assert moved_reply.board_id == target_board.id
    assert moved_reply.thread_id == target_thread.id
    assert moved_reply.file_path =~ ~r|^/#{target_board.uri}/src/\d+-#{reply.id}\.png$|
    refute File.exists?(Eirinchan.Uploads.filesystem_path(old_file))
    assert File.exists?(Eirinchan.Uploads.filesystem_path(moved_reply.file_path))

    assert {:ok, [reloaded_source_thread]} = Posts.get_thread(source_board, source_thread.id)
    assert reloaded_source_thread.id == source_thread.id

    assert {:ok, [_target_thread, moved_reply_from_target]} =
             Posts.get_thread(target_board, target_thread.id)

    assert moved_reply_from_target.id == reply.id

    assert File.read!(
             Path.join([Build.board_root(), target_board.uri, "res", "#{target_thread.id}.html"])
           ) =~
             "Movable reply"
  end
end
