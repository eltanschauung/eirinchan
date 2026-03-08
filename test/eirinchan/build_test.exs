defmodule Eirinchan.BuildTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.Build
  alias Eirinchan.BuildQueue
  alias Eirinchan.Posts
  alias Eirinchan.Runtime.Config

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-build-themes-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  test "posting rebuilds paginated board, thread, and api files" do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    File.rm_rf!(Build.board_root())

    board =
      board_fixture(%{
        config_overrides: %{threads_per_page: 1, threads_preview: 1, api: %{enabled: true}}
      })

    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")
    request = %{referer: "http://example.test/#{board.uri}/index.html"}

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening post body",
                 "subject" => "Opening subject",
                 "post" => config.button_newtopic
               },
               config: config,
               request: request
             )

    assert {:ok, second_thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Second thread body",
                 "subject" => "Second thread subject",
                 "post" => config.button_newtopic
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
                 "post" => config.button_reply
               },
               config: config,
               request: request
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    page_two_path = Path.join(board_dir, "2.html")
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])
    thread_json_path = Path.join([board_dir, config.dir.res, "#{thread.id}.json"])
    page_zero_json_path = Path.join(board_dir, "0.json")
    catalog_json_path = Path.join(board_dir, "catalog.json")
    catalog_html_path = Path.join(board_dir, config.file_catalog)
    threads_json_path = Path.join(board_dir, "threads.json")

    assert File.read!(index_path) =~ "Opening subject"
    assert File.read!(index_path) =~ "Reply body"
    assert File.read!(index_path) =~ ~s(name="delete_post_id")
    assert File.read!(page_two_path) =~ "Second thread subject"
    assert File.read!(catalog_html_path) =~ "Second thread subject"
    assert File.read!(catalog_html_path) =~ ~s(name="delete_post_id")
    assert File.read!(thread_path) =~ "Reply body"
    assert File.read!(thread_path) =~ ~s(name="delete_post_id")
    assert Jason.decode!(File.read!(thread_json_path))["posts"] |> length() == 2

    assert Jason.decode!(File.read!(page_zero_json_path))["threads"]
           |> hd()
           |> Map.fetch!("posts")
           |> hd()
           |> Map.fetch!("no") == thread.id

    assert Jason.decode!(File.read!(Path.join(board_dir, "1.json")))["threads"]
           |> hd()
           |> Map.fetch!("posts")
           |> hd()
           |> Map.fetch!("no") == second_thread.id

    assert Jason.decode!(File.read!(catalog_json_path)) |> length() == 2
    assert Jason.decode!(File.read!(threads_json_path)) |> length() == 2
  end

  test "posting rebuilds media references into static html and json outputs" do
    File.rm_rf!(Build.board_root())

    board = board_fixture(%{config_overrides: %{api: %{enabled: true}}})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")
    upload = upload_fixture("thread.png", "thread-bytes")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening post body",
                 "file" => upload,
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])
    thread_json_path = Path.join([board_dir, config.dir.res, "#{thread.id}.json"])

    assert File.read!(index_path) =~ thread.thumb_path
    assert File.read!(thread_path) =~ thread.thumb_path
    assert File.exists?(Path.join(board_dir, "thumb/#{thread.id}s.png"))

    assert %{"posts" => [op]} = Jason.decode!(File.read!(thread_json_path))
    assert op["filename"] == "thread"
    assert op["ext"] == ".png"
    assert op["fsize"] == thread.file_size
    assert op["w"] == 16
    assert op["h"] == 16
  end

  test "embed posts rebuild into static html and api outputs" do
    File.rm_rf!(Build.board_root())

    board = board_fixture(%{config_overrides: %{api: %{enabled: true}}})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening post body",
                 "embed" => "https://youtu.be/dQw4w9WgXcQ",
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])
    thread_json_path = Path.join([board_dir, config.dir.res, "#{thread.id}.json"])

    assert File.read!(index_path) =~ ~s(class="video-container")
    assert File.read!(thread_path) =~ "img.youtube.com/vi/dQw4w9WgXcQ/0.jpg"

    assert %{"posts" => [op]} = Jason.decode!(File.read!(thread_json_path))
    assert op["embed"] == "https://youtu.be/dQw4w9WgXcQ"
  end

  test "non-image uploads build placeholder thumb references and omit image dimensions in api" do
    File.rm_rf!(Build.board_root())

    board =
      board_fixture(%{
        config_overrides: %{
          api: %{enabled: true},
          allowed_ext_files: [".png", ".jpg", ".jpeg", ".gif", ".txt"]
        }
      })

    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")
    upload = raw_upload_fixture("notes.txt", "hello")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening post body",
                 "file" => upload,
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_json_path = Path.join([board_dir, config.dir.res, "#{thread.id}.json"])

    assert File.read!(index_path) =~ thread.thumb_path
    assert File.exists?(Path.join(board_dir, "thumb/#{thread.id}s.png"))

    assert %{"posts" => [op]} = Jason.decode!(File.read!(thread_json_path))
    assert op["filename"] == "notes"
    assert op["ext"] == ".txt"
    assert op["fsize"] == byte_size("hello")
    refute Map.has_key?(op, "w")
    refute Map.has_key?(op, "h")
  end

  test "multi-file uploads build extra file references into static html and api" do
    File.rm_rf!(Build.board_root())

    board = board_fixture(%{config_overrides: %{api: %{enabled: true}}})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening post body",
                 "files" => [
                   upload_fixture("first.png", "first"),
                   upload_fixture("second.gif", "second")
                 ],
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    [extra] = thread.extra_files
    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_json_path = Path.join([board_dir, config.dir.res, "#{thread.id}.json"])

    assert File.read!(index_path) =~ thread.thumb_path
    assert File.read!(index_path) =~ extra.thumb_path

    assert %{"posts" => [op]} = Jason.decode!(File.read!(thread_json_path))
    assert length(op["extra_files"]) == 1
    assert hd(op["extra_files"])["ext"] == ".gif"
  end

  test "spoiler uploads build spoiler thumbs and expose spoiler flags in api" do
    File.rm_rf!(Build.board_root())

    board = board_fixture(%{config_overrides: %{api: %{enabled: true}}})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening post body",
                 "files" => [
                   upload_fixture("first.png", "first"),
                   upload_fixture("second.gif", "second")
                 ],
                 "spoiler" => "1",
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    [extra] = thread.extra_files
    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_json_path = Path.join([board_dir, config.dir.res, "#{thread.id}.json"])

    assert File.read!(index_path) =~ thread.thumb_path
    assert File.read!(index_path) =~ extra.thumb_path

    assert %{"posts" => [op]} = Jason.decode!(File.read!(thread_json_path))
    assert op["spoiler"] == 1
    assert hd(op["extra_files"])["spoiler"] == 1
  end

  test "static outputs render stored user flag labels" do
    File.rm_rf!(Build.board_root())

    board =
      board_fixture(%{
        config_overrides: %{user_flag: true, user_flags: %{"sau" => "Sauce", "spc" => "Space"}}
      })

    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening post body",
                 "user_flag" => "sau",
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])

    refute File.read!(index_path) =~ "Flags:"
    refute File.read!(thread_path) =~ "Flags:"
  end

  test "static outputs render stored OP tags" do
    File.rm_rf!(Build.board_root())

    board =
      board_fixture(%{
        config_overrides: %{allowed_tags: %{"A" => "Anime", "M" => "Music"}}
      })

    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening post body",
                 "tag" => "A",
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])

    assert File.read!(index_path) =~ "Tag: Anime"
    assert File.read!(thread_path) =~ "Tag: Anime"
  end

  test "static outputs render the boardlist" do
    File.rm_rf!(Build.board_root())

    board_fixture(%{uri: "meta", title: "Meta"})
    board = board_fixture(%{uri: "tech", title: "Technology"})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Opening post body", "post" => config.button_newtopic},
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])

    assert File.read!(index_path) =~ ~s(href="/meta/index.html")
    assert File.read!(thread_path) =~ ~s(href="/meta/index.html")
  end

  test "static outputs render poster tripcodes" do
    File.rm_rf!(Build.board_root())

    board = board_fixture()
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "name" => "Anon#secret",
                 "body" => "Opening post body",
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])

    assert File.read!(thread_path) =~ thread.tripcode
  end

  test "slugified threads build canonical and legacy html files" do
    File.rm_rf!(Build.board_root())

    board = board_fixture(%{config_overrides: %{slugify: true}})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "subject" => "Slug file subject",
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    canonical_path = Path.join([board_dir, config.dir.res, "#{thread.id}-slug-file-subject.html"])
    legacy_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])

    assert File.read!(canonical_path) =~ "Opening body"
    assert File.read!(legacy_path) =~ "Opening body"
  end

  test "thread state updates rebuild static board and thread outputs" do
    File.rm_rf!(Build.board_root())

    board = board_fixture()
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "subject" => "Managed subject",
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    assert {:ok, _updated_thread} =
             Posts.update_thread_state(
               board,
               thread.id,
               %{"sticky" => "true", "locked" => "true"},
               config: config
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])

    assert File.read!(index_path) =~ "[Sticky]"
    assert File.read!(index_path) =~ "[Locked]"
    assert File.read!(thread_path) =~ "[Sticky]"
    assert File.read!(thread_path) =~ "[Locked]"
  end

  test "deleting posts updates static thread and board outputs" do
    File.rm_rf!(Build.board_root())

    board = board_fixture(%{config_overrides: %{slugify: true}})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")
    request = %{referer: "http://example.test/#{board.uri}/index.html"}

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "subject" => "Delete subject",
                 "password" => "threadpw",
                 "post" => config.button_newtopic
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
                 "post" => config.button_reply
               },
               config: config,
               request: request
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])

    canonical_thread_path =
      Path.join([board_dir, config.dir.res, "#{thread.id}-delete-subject.html"])

    assert File.read!(thread_path) =~ "Reply body"

    assert {:ok, %{thread_deleted: false}} =
             Posts.delete_post(board, reply.id, "replypw", config: config)

    refute File.read!(thread_path) =~ "Reply body"

    assert {:ok, %{thread_deleted: true}} =
             Posts.delete_post(board, thread.id, "threadpw", config: config)

    refute File.exists?(thread_path)
    refute File.exists?(canonical_thread_path)
  end

  test "fileboard static outputs use filenames as titles when subjects are absent" do
    File.rm_rf!(Build.board_root())

    board =
      board_fixture(%{
        config_overrides: %{
          fileboard: true,
          force_body_op: false,
          allowed_ext_files: [".png", ".jpg", ".jpeg", ".gif", ".txt"]
        }
      })

    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => ".",
                 "file" => raw_upload_fixture("docs.txt", "hello"),
                 "post" => config.button_newtopic
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    index_path = Path.join(board_dir, config.file_index)
    thread_path = Path.join([board_dir, config.dir.res, "#{thread.id}.html"])

    assert File.read!(index_path) =~ "docs.txt"
    assert File.read!(index_path) =~ "Fileboard: 1 file"
    assert File.read!(thread_path) =~ "docs.txt"
  end

  test "deferred generation queues build jobs instead of writing immediately" do
    File.rm_rf!(Build.board_root())

    board = board_fixture(%{config_overrides: %{generation_strategy: "defer"}})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"body" => "Opening body", "subject" => "Deferred thread", "post" => "New Topic"},
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    refute File.exists?(Path.join([board_dir, config.dir.res, "#{thread.id}.html"]))
    refute File.exists?(Path.join(board_dir, config.file_index))
    assert Enum.map(BuildQueue.list_pending(), & &1.kind) == ["thread", "indexes"]
  end
end
