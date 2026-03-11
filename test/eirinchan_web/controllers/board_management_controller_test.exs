defmodule EirinchanWeb.BoardManagementControllerTest do
  use EirinchanWeb.ConnCase, async: false

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-board-themes-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  test "creates, updates, shows, and deletes boards over HTTP", %{conn: conn} do
    moderator = moderator_fixture()

    conn =
      conn
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")

    conn =
      post(conn, ~p"/manage/boards", %{
        uri: "tech",
        title: "Technology",
        subtitle: "Wired",
        config_overrides: %{force_body: true}
      })

    assert %{
             "data" => %{
               "uri" => "tech",
               "title" => "Technology",
               "subtitle" => "Wired",
               "config_overrides" => %{"force_body" => true}
             }
           } = json_response(conn, 201)

    assert %{"data" => %{"uri" => "tech"}} =
             conn
             |> recycle()
             |> login_moderator(moderator)
             |> get(~p"/manage/boards/tech")
             |> json_response(200)

    assert %{"data" => %{"title" => "Technology+"}} =
             conn
             |> recycle()
             |> login_moderator(moderator)
             |> put_secure_manage_token()
             |> patch(~p"/manage/boards/tech", %{title: "Technology+"})
             |> json_response(200)

    assert response(
             conn
             |> recycle()
             |> login_moderator(moderator)
             |> put_secure_manage_token()
             |> delete(~p"/manage/boards/tech"),
             204
           )

    assert %{"error" => "not_found"} =
             conn
             |> recycle()
             |> login_moderator(moderator)
             |> get(~p"/manage/boards/tech")
             |> json_response(404)
  end

  test "board page loads through the DB-backed board context", %{conn: conn} do
    board_fixture(%{uri: "meta", title: "Meta"})
    board = board_fixture(%{title: "Technology", subtitle: "Wired"})

    response =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert response =~ "/#{board.uri}/ - Technology"
    assert response =~ "Wired"

    assert response =~
             ~s(<script type="text/javascript">var active_page = "index", board_name = "#{board.uri}";</script>)

    assert response =~ ~s(href="/stylesheets/style.css)
    assert response =~ ~s(id="stylesheet" href="/stylesheets/yotsuba.css)
    assert response =~ ~s(data-stylesheet="yotsuba.css")
    assert response =~ ~s(src="/main.js)
    assert response =~ ~s(title="Meta">meta</a>)
    assert response =~ ~s(action="/search.php")
    assert response =~ ~s(name="board" value="#{board.uri}")
    assert response =~ "No threads yet."
    refute response =~ ~s(name="user_flag")
    assert response =~ ~s(name="embed")
  end

  test "board pages send no-store cache headers", %{conn: conn} do
    board = board_fixture(%{uri: "cachetest", title: "Cache Test"})

    conn =
      conn
      |> get(~p"/#{board.uri}")

    assert html_response(conn, 200) =~ "/#{board.uri}/ - #{board.title}"

    assert get_resp_header(conn, "cache-control") == [
             "no-store, no-cache, must-revalidate, max-age=0"
           ]

    assert get_resp_header(conn, "pragma") == ["no-cache"]
    assert get_resp_header(conn, "expires") == ["0"]
  end

  test "board page renders archive link from board config", %{conn: conn} do
    board =
      board_fixture(%{
        uri: "arc",
        title: "Archive Test",
        config_overrides: %{archive_url: "https://archive.example.test/arc/"}
      })

    response =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert response =~ ~s(href="https://archive.example.test/arc/")
    assert response =~ "[Archive]"
  end

  test "board page renders updater controls and refresh target", %{conn: conn} do
    board = board_fixture(%{uri: "update", title: "Update Test"})

    response =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert response =~ ~s(id="updater")
    assert response =~ ~s(id="update_thread")
    assert response =~ ~s(class="live-page-indicator")
    assert response =~ ~s(id="auto_update_status")
    assert response =~ ~s(id="update_secs")
    assert response =~ ~s(id="board-refresh-target")
  end

  test "board page renders watch links for threads", %{conn: conn} do
    board = board_fixture(%{uri: "watchlinks", title: "Watch Links"})
    _thread = thread_fixture(board, %{body: "Watching"})

    response =
      conn
      |> put_req_cookie("browser_token", "token-1234567890123456")
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert response =~ ~s(data-thread-watch)
    assert response =~ "[Watch]"
  end

  test "board page uses configured catalog name in search links", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")

    board =
      board_fixture(%{
        uri: "orin",
        title: "Orin Test",
        config_overrides: %{catalog_name: "Orin"}
      })

    response =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert response =~ ~s(href="/#{board.uri}/catalog.html")
    assert response =~ "[Orin]"
    refute response =~ "[Catalog]"
  end

  test "board page fragment renders refresh target only", %{conn: conn} do
    board = board_fixture(%{uri: "frag", title: "Fragment Test"})

    response =
      conn
      |> get(~p"/#{board.uri}?fragment=1")
      |> html_response(200)

    assert response =~ ~s(id="board-refresh-target")
    refute response =~ ~s(<html)
    refute response =~ ~s(action="/search.php")
  end

  test "catalog fragment renders grid only", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    board = board_fixture(%{uri: "catfrag", title: "Catalog Fragment"})

    response =
      conn
      |> get(~p"/#{board.uri}/catalog.html?fragment=1")
      |> html_response(200)

    assert response =~ ~s(id="Grid")
    refute response =~ ~s(<html)
    refute response =~ ~s(Return to Index)
  end

  test "board page renders global message as a blotter above the search form", %{conn: conn} do
    :ok = Eirinchan.Settings.persist_instance_config(%{global_message: "Important notice"})
    board = board_fixture(%{uri: "blottertest", title: "Blotter Test"})

    response =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert response =~ ~s(<div class="blotter">Important notice</div>)

    blotter_pos =
      response
      |> :binary.match(~s(<div class="blotter">Important notice</div>))
      |> elem(0)

    search_pos =
      response
      |> :binary.match("<!-- Start Search Form -->")
      |> elem(0)

    assert blotter_pos < search_pos
  end

  test "board pages honor explicit post form row toggles", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          user_flags: %{"sau" => "Sauce"},
          enable_embedding: true,
          post_form_embed: false
        }
      })

    response =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert response =~ ~s(name="user_flag")
    refute response =~ ~s(name="embed")
  end

  test "board pages render previews, omitted counts, and pagination", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{threads_per_page: 1, threads_preview: 1}})
    thread = thread_fixture(board, %{body: "Older body", subject: "Older"})

    conn
    |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
    |> post(~p"/#{board.uri}/post", %{
      "thread" => Integer.to_string(thread.id),
      "body" => "Reply one",
      "post" => "New Reply"
    })

    conn
    |> recycle()
    |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
    |> post(~p"/#{board.uri}/post", %{
      "thread" => Integer.to_string(thread.id),
      "body" => "Reply two",
      "post" => "New Reply"
    })

    conn
    |> recycle()
    |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
    |> post(~p"/#{board.uri}/post", %{
      "body" => "Newer body",
      "subject" => "Newer",
      "post" => "New Topic"
    })

    first_page =
      conn
      |> recycle()
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    second_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/2.html")
      |> html_response(200)

    assert first_page =~ "Newer"
    assert first_page =~ "/#{board.uri}/2.html"
    assert first_page =~ ~s(id="post-moderation-fields")
    assert first_page =~ ~s(id="delete_)
    assert second_page =~ "Older"
    assert second_page =~ "1 posts"
    assert second_page =~ "Reply two"
    assert second_page =~ ~s(id="post-moderation-fields")
    assert second_page =~ ~s(id="delete_)
  end

  test "index.html resolves to the first board page", %{conn: conn} do
    board = board_fixture(%{uri: "meta#{System.unique_integer([:positive])}", title: "Meta"})

    page =
      conn
      |> get("/#{board.uri}/index.html")
      |> html_response(200)

    assert page =~ "/#{board.uri}/ - #{board.title}"
  end

  test "board pages render formatted quote links in thread previews", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board, %{body: "Opening body"})
    reply_fixture(board, thread, %{body: ">>#{thread.id}\n>quoted line"})

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert page =~ ~s(href="/#{board.uri}/res/#{thread.id}.html##{thread.id}")
    assert page =~ ~s(class="quote")
  end

  test "catalog page renders thread summaries across board pages", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    board = board_fixture(%{config_overrides: %{threads_per_page: 1}})

    conn
    |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
    |> post(~p"/#{board.uri}/post", %{
      "body" => "First body",
      "subject" => "First thread",
      "post" => "New Topic"
    })

    conn
    |> recycle()
    |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
    |> post(~p"/#{board.uri}/post", %{
      "body" => "Second body",
      "subject" => "Second thread",
      "post" => "New Topic"
    })

    catalog_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/catalog.html")
      |> html_response(200)

    assert catalog_page =~ "Catalog"
    assert catalog_page =~ "First thread"
    assert catalog_page =~ "Second thread"
    assert catalog_page =~ ~s(name="delete_post_id")
  end

  test "catalog page paginates independently when enabled", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")

    board =
      board_fixture(%{
        config_overrides: %{
          threads_per_page: 1,
          catalog_pagination: true,
          catalog_threads_per_page: 2
        }
      })

    for subject <- ["First thread", "Second thread", "Third thread"] do
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "#{subject} body",
        "subject" => subject,
        "post" => "New Topic"
      })
    end

    first_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/catalog.html")
      |> html_response(200)

    second_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/catalog/2.html")
      |> html_response(200)

    assert first_page =~ ~s(href="/#{board.uri}/catalog/2.html")
    assert first_page =~ "Third thread"
    assert first_page =~ "Second thread"
    refute first_page =~ "First thread"
    assert second_page =~ "First thread"
    refute second_page =~ "Second thread"
  end

  test "catalog page renders the distribution chrome shell", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    board = board_fixture(%{uri: "bant", title: "International Random"})
    thread_fixture(board, %{body: "First body", subject: "First thread"})

    page =
      conn
      |> get("/#{board.uri}/catalog.html")
      |> html_response(200)

    assert page =~ ~s(class="8chan vichan is-not-moderator theme-catalog active-catalog")
    assert page =~ ~s(data-stylesheet="yotsuba.css")
    assert page =~ ~s(href="/stylesheets/style.css)
    assert page =~ ~s(id="stylesheet" href="/stylesheets/yotsuba.css)
    assert page =~ "Return to Index"
    assert page =~ "Sort by:"
    assert page =~ ~s(id="Grid")
    assert page =~ "Tinyboard + vichan 5.2.2 +"
    assert page =~ ~s(href="https://github.com/username/eirinchan-v1")
  end

  test "catalog page renders formatted body excerpts", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    board = board_fixture()
    thread_fixture(board, %{body: ">quoted\nsecond line"})

    page =
      conn
      |> get("/#{board.uri}/catalog.html")
      |> html_response(200)

    assert page =~ ~s(class="quote")
    assert page =~ "second line"
    assert page =~ "<br/>"
  end

  test "board page respects field disable flags and single-file selector mode", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          field_disable_name: true,
          field_disable_email: true,
          field_disable_subject: true,
          field_disable_password: true,
          max_images: 1
        }
      })

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    refute page =~ ~s(name="name")
    refute page =~ ~s(name="email")
    refute page =~ ~s(name="subject")
    refute page =~ ~s(name="password" placeholder="Password")
    assert page =~ ~s(name="file")
    refute page =~ ~s(name="files[]")
    refute page =~ "multiple"
  end

  test "board page exposes multi-file selector when max_images is greater than one", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{max_images: 3}})

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert page =~ ~s(name="files[]")
    assert page =~ "multiple"
  end

  test "board page renders user flag select with the configured default", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          default_user_flag: "spc",
          user_flags: %{"sau" => "Sauce", "spc" => "Space"}
        }
      })

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    document = Floki.parse_document!(page)

    assert Floki.find(document, ~s(select[name="user_flag"])) != []
    assert Floki.find(document, ~s(option[value="spc"][selected])) != []
    assert page =~ "Sauce"
    assert page =~ "Space"
  end

  test "board page renders freeform user flag input when multiple_flags is enabled", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          multiple_flags: true,
          default_user_flag: "country,sau",
          user_flags: %{"country" => "Country", "sau" => "Sauce", "spc" => "Space"}
        }
      })

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    document = Floki.parse_document!(page)

    assert Floki.find(document, ~s(input[name="user_flag"][type="text"])) != []
    assert page =~ "country,sau"
    assert Floki.find(document, ~s(select[name="user_flag"])) == []
  end

  test "board page renders a no_country checkbox when country opt-out is enabled", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{country_flags: true, allow_no_country: true}})

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    document = Floki.parse_document!(page)

    assert Floki.find(document, ~s(input[name="no_country"][type="checkbox"])) != []
  end

  test "board page renders cite hooks that target the main post form", %{
    conn: conn
  } do
    board = board_fixture()
    thread = thread_fixture(board, %{body: "Thread body"})
    _reply = reply_fixture(board, thread, %{body: "Reply body"})

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    document = Floki.parse_document!(page)

    assert Floki.find(document, ~s(a[data-quick-reply-thread="#{thread.id}"][data-quote-to])) !=
             []

    assert Floki.find(document, ~s(form#new-thread-form[data-remember-stuff])) != []
    assert Floki.find(document, ~s(form#new-thread-form textarea[data-post-body])) != []
  end

  test "board page renders allowed OP tag choices", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{allowed_tags: %{"A" => "Anime", "M" => "Music"}}})

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    document = Floki.parse_document!(page)

    assert Floki.find(document, ~s(select[name="tag"])) != []
    assert page =~ "Anime"
    assert page =~ "Music"
  end

  test "board page does not expose raw html or capcode posting controls", %{conn: conn} do
    board = board_fixture()
    moderator = moderator_fixture()

    page =
      conn
      |> login_moderator(moderator)
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    document = Floki.parse_document!(page)

    assert Floki.find(document, ~s(input[name="capcode"])) == []
    assert Floki.find(document, ~s(input[name="raw"][type="checkbox"])) == []
  end

  test "board page renders antispam and captcha inputs when enabled", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          hidden_input_name: "hash",
          hidden_input_hash: "expected",
          antispam_question: "2+2?",
          captcha: %{enabled: true, provider: "recaptcha", expected_response: "ok"}
        }
      })

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    document = Floki.parse_document!(page)

    assert Floki.find(document, ~s(input[name="hash"][type="hidden"][value="expected"])) != []
    assert page =~ "2+2?"
    assert Floki.find(document, ~s(input[name="antispam_answer"])) != []
    assert Floki.find(document, ~s(input[name="g-recaptcha-response"])) != []
    assert Floki.find(document, ~s(input[name="g-recaptcha-response"][data-captcha-lazy])) != []
  end

  test "board page respects captcha mode for OP forms", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          captcha: %{enabled: true, provider: "native", mode: "op", challenge: "2 + 2 = ?"}
        }
      })

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert page =~ "2 + 2 = ?"
    assert Floki.find(Floki.parse_document!(page), ~s(input[name="captcha"])) != []
  end

  test "board page exposes rememberStuff hooks for the main post form", %{conn: conn} do
    board = board_fixture()
    _thread = thread_fixture(board)

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    document = Floki.parse_document!(page)

    assert Floki.find(
             document,
             ~s(form#new-thread-form[data-remember-stuff][data-draft-key="new"])
           ) != []
  end

  test "board pages trigger build-on-load index generation when configured", %{conn: conn} do
    alias Eirinchan.Build

    board = board_fixture(%{config_overrides: %{generation_strategy: "build_on_load"}})
    File.rm_rf!(Path.join(Build.board_root(), board.uri))

    page =
      conn
      |> get(~p"/#{board.uri}")
      |> html_response(200)

    assert page =~ "/#{board.uri}/ - #{board.title}"
    assert File.exists?(Path.join([Build.board_root(), board.uri, "index.html"]))
  end

  test "fileboard pages use filenames as thread titles when subjects are absent", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    board = board_fixture(%{config_overrides: %{fileboard: true, force_body_op: false}})

    conn
    |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
    |> post(~p"/#{board.uri}/post", %{
      "body" => ".",
      "file" => upload_fixture("notes.png", "hello"),
      "post" => "New Topic"
    })

    page =
      conn
      |> recycle()
      |> get("/#{board.uri}")
      |> html_response(200)

    catalog_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/catalog.html")
      |> html_response(200)

    assert page =~ "notes.png"
    assert page =~ "Fileboard: 1 file"
    assert catalog_page =~ "notes.png"
  end

  test "catalog cards expose full image paths for image hover", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    board = board_fixture()

    %{id: id} =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "hover me",
        "file" => upload_fixture("hover.png", "hover"),
        "json_response" => "1",
        "post" => "New Topic"
      })
      |> json_response(200)
      |> then(&%{id: &1["id"]})

    {:ok, [thread | _]} = Eirinchan.Posts.get_thread(board, id)

    catalog_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/catalog.html")
      |> html_response(200)

    assert catalog_page =~ ~s(data-fullimage="#{thread.file_path}")
  end
end
