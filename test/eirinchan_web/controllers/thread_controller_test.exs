defmodule EirinchanWeb.ThreadControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.Posts
  alias Eirinchan.Runtime.Config
  alias Eirinchan.ThreadPaths

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-thread-themes-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  test "plain thread urls redirect to the canonical slug path", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{slugify: true}})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "www.example.com")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "subject" => "Thread slug test",
                 "body" => "Opening body",
                 "post" => "New Topic"
               },
               config: config,
               request: %{referer: "http://www.example.com/#{board.uri}/index.html"}
             )

    conn = get(conn, "/#{board.uri}/res/#{thread.id}.html")

    assert redirected_to(conn) == ThreadPaths.thread_path(board, thread, config)
  end

  test "canonical thread urls render with a return link to the current board page", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{slugify: true, threads_per_page: 1}})
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "www.example.com")
    request = %{referer: "http://www.example.com/#{board.uri}/index.html"}

    assert {:ok, older_thread, _meta} =
             Posts.create_post(
               board,
               %{"subject" => "Older subject", "body" => "Older body", "post" => "New Topic"},
               config: config,
               request: request
             )

    assert {:ok, _newer_thread, _meta} =
             Posts.create_post(
               board,
               %{"subject" => "Newer subject", "body" => "Newer body", "post" => "New Topic"},
               config: config,
               request: request
             )

    thread_path = ThreadPaths.thread_path(board, older_thread, config)
    page = conn |> get(thread_path) |> html_response(200)

    assert page =~ ~s(href="/#{board.uri}/2.html")
    assert page =~ "Older body"
    assert page =~ ~s(name="delete_post_id")
  end

  test "thread reply form respects reply field toggles and multi-file selector mode", %{
    conn: conn
  } do
    board =
      board_fixture(%{
        config_overrides: %{
          field_disable_name: true,
          field_disable_email: true,
          field_disable_reply_subject: true,
          field_disable_password: true,
          max_images: 2
        }
      })

    thread = thread_fixture(board, %{body: "Thread body", subject: "Thread subject"})
    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)
    document = Floki.parse_document!(page)

    reply_form =
      document
      |> Floki.find("form")
      |> Enum.find(fn form ->
        Floki.find(form, ~s(input[name="thread"][value="#{thread.id}"])) != []
      end)

    assert reply_form
    assert Floki.find(reply_form, ~s(input[name="name"])) == []
    assert Floki.find(reply_form, ~s(input[name="email"])) == []
    assert Floki.find(reply_form, ~s(input[name="subject"])) == []
    assert Floki.find(reply_form, ~s(input[name="password"])) == []
    assert Floki.find(reply_form, ~s(input[name="files[]"][multiple])) != []
  end

  test "thread pages render stored user flag labels", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{user_flag: true, user_flags: %{"sau" => "Sauce", "spc" => "Space"}}
      })

    config = Config.compose(nil, %{}, board.config_overrides, request_host: "www.example.com")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "user_flag" => "sau",
                 "post" => "New Topic"
               },
               config: config,
               request: %{referer: "http://www.example.com/#{board.uri}/index.html"}
             )

    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)

    assert page =~ ~s(title="Sauce")
  end

  test "thread pages hide rendered flags when display_flags is disabled", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          display_flags: false,
          user_flags: %{"sau" => "Sauce"},
          uri_flags: "static/flags/%s.png"
        }
      })

    config = Config.compose(nil, %{}, board.config_overrides, request_host: "www.example.com")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "user_flag" => "sau",
                 "post" => "New Topic"
               },
               config: config,
               request: %{referer: "http://www.example.com/#{board.uri}/index.html"}
             )

    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)

    refute page =~ ~s(title="Sauce")
    refute page =~ ~s(class="flag")
  end

  test "thread pages render configured embed rows and stored youtube embeds", %{conn: conn} do
    board = board_fixture()
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "www.example.com")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "embed" => "https://youtu.be/dQw4w9WgXcQ",
                 "post" => "New Topic"
               },
               config: config,
               request: %{referer: "http://www.example.com/#{board.uri}/index.html"}
             )

    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)

    assert page =~ ~s(name="embed")
    assert page =~ ~s(class="video-container")
    assert page =~ "img.youtube.com/vi/dQw4w9WgXcQ/0.jpg"
  end

  test "thread pages render stored OP tags", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{allowed_tags: %{"A" => "Anime", "M" => "Music"}}
      })

    config = Config.compose(nil, %{}, board.config_overrides, request_host: "www.example.com")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Opening body",
                 "tag" => "A",
                 "post" => "New Topic"
               },
               config: config,
               request: %{referer: "http://www.example.com/#{board.uri}/index.html"}
             )

    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)

    assert page =~ "Tag: Anime"
  end

  test "thread pages render the boardlist", %{conn: conn} do
    board_fixture(%{uri: "meta", title: "Meta"})
    board = board_fixture()
    thread = thread_fixture(board)

    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)

    assert page =~ ~s(title="Meta">meta</a>)
    assert page =~ ~s(title="#{board.title}">#{board.uri}</a>)
    assert page =~ ~s(var active_page = "thread", board_name = "#{board.uri}")
    assert page =~ ~s(src="/main.js)
  end

  test "thread pages render the distribution chrome shell", %{conn: conn} do
    board = board_fixture(%{uri: "bant", title: "International Random"})
    thread = thread_fixture(board, %{body: "Thread body"})

    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)

    assert page =~ ~s(class="8chan vichan is-not-moderator active-thread")
    assert page =~ ~s(data-stylesheet="yotsuba.css")
    assert page =~ ~s(href="/stylesheets/style.css)
    assert page =~ ~s(id="stylesheet" href="/stylesheets/yotsuba.css)
    assert page =~ ~s(src="/main.js)
    assert page =~ ~s(src="/b.php")
    refute page =~ "[Catalog]"
    assert page =~ ~s(class="boardlist")
  end

  test "thread reply forms respect captcha mode for replies only", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          captcha: %{enabled: true, provider: "native", mode: "reply", challenge: "reply check"}
        }
      })

    thread = thread_fixture(board)
    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)
    document = Floki.parse_document!(page)

    assert page =~ "reply check"
    assert Floki.find(document, ~s(input[name="captcha"])) != []
    assert Floki.find(document, ~s(label[data-captcha-lazy] input[name="captcha"])) != []

    board_page = conn |> recycle() |> get("/#{board.uri}") |> html_response(200)
    refute board_page =~ "reply check"
  end

  test "thread reply form exposes rememberStuff hooks", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)

    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)
    document = Floki.parse_document!(page)

    assert Floki.find(
             document,
             ~s(form#reply-form[data-remember-stuff][data-draft-key="#{thread.id}"])
           ) != []
  end

  test "thread pages render poster tripcodes", %{conn: conn} do
    board = board_fixture()
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "www.example.com")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{"name" => "Anon#secret", "body" => "Opening body", "post" => "New Topic"},
               config: config,
               request: %{referer: "http://www.example.com/#{board.uri}/index.html"}
             )

    page = conn |> get("/#{board.uri}/res/#{thread.id}.html") |> html_response(200)

    assert page =~ thread.tripcode
  end

  test "thread pages show moderator controls and ip links for admins", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    thread = thread_fixture(board, %{ip_subnet: "198.51.100.7"})
    _reply = reply_fixture(board, thread, %{ip_subnet: "198.51.100.7"})

    page =
      conn
      |> login_moderator(moderator)
      |> get("/#{board.uri}/res/#{thread.id}.html")
      |> html_response(200)

    assert page =~ ~s(class="controls op")
    assert page =~ ~s(href="/mod.php?/IP/198.51.100.7")
    assert page =~ "[D]"
    assert page =~ "[Sticky]"
    assert page =~ "[Lock]"
    assert page =~ "[Edit]"
  end

  test "thread page renders quote links and reply form hooks for cite insertion", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board, %{body: "Thread body"})
    reply = reply_fixture(board, thread, %{body: "Reply body"})

    page =
      conn
      |> get("/#{board.uri}/res/#{thread.id}.html")
      |> html_response(200)

    document = Floki.parse_document!(page)

    assert Floki.find(document, ~s(form#reply-form[data-thread-reply-form])) != []
    assert Floki.find(document, ~s(textarea[data-post-body])) != []
    assert Floki.find(document, ~s(a[data-quote-to="#{thread.id}"])) != []
    assert Floki.find(document, ~s(a[data-quote-to="#{reply.id}"])) != []
  end

  test "thread pages render vichan-style body quote links", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board, %{body: "Opening body"})
    reply = reply_fixture(board, thread, %{body: ">>#{thread.id}\n>quoted line"})

    page =
      conn
      |> get("/#{board.uri}/res/#{thread.id}.html")
      |> html_response(200)

    assert page =~ ~s(href="/#{board.uri}/res/#{thread.id}.html##{thread.id}")
    assert page =~ ~s(class="quote")
    assert page =~ Integer.to_string(reply.id)
  end

  test "thread pages trigger build-on-load thread generation when configured", %{conn: conn} do
    alias Eirinchan.Build

    board = board_fixture(%{config_overrides: %{generation_strategy: "build_on_load"}})
    File.rm_rf!(Path.join(Build.board_root(), board.uri))
    thread = thread_fixture(board, %{body: "Thread body", subject: "Thread subject"})

    thread_path = Path.join([Build.board_root(), board.uri, "res", "#{thread.id}.html"])
    refute File.exists?(thread_path)

    page =
      conn
      |> get("/#{board.uri}/res/#{thread.id}.html")
      |> html_response(200)

    assert page =~ "Thread body"
    assert File.exists?(thread_path)
  end

  test "fileboard threads use filenames as page titles when subjects are absent", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{fileboard: true, force_body_op: false}})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => ".",
        "file" => upload_fixture("manual.png", "readme"),
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => thread_id} = json_response(conn, 200)

    page =
      conn
      |> recycle()
      |> get("/#{board.uri}/res/#{thread_id}.html")
      |> html_response(200)

    assert page =~ "manual.png"
    assert page =~ "Fileboard: 1 file"
  end
end
