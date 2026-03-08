defmodule EirinchanWeb.PostControllerTest do
  use EirinchanWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  test "classic posting redirects OP creation to the thread page", %{conn: conn} do
    board = board_fixture(%{title: "Technology"})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "name" => "anon",
        "subject" => "launch",
        "body" => "first post",
        "post" => "New Topic"
      })

    thread_path = redirected_to(conn)
    thread_page = conn |> recycle() |> get(thread_path) |> html_response(200)

    assert thread_path =~ ~r|/#{board.uri}/res/\d+\.html|
    assert thread_page =~ "first post"
    assert thread_page =~ "launch"

    conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "name" => "anon",
        "email" => "noko",
        "subject" => "launch",
        "body" => "second post",
        "post" => "New Topic"
      })

    thread_path = redirected_to(conn) |> String.split("#") |> hd()
    thread_page = conn |> recycle() |> get(thread_path) |> html_response(200)

    assert redirected_to(conn) =~ ~r|/#{board.uri}/res/\d+\.html|
    assert thread_page =~ "second post"
    assert thread_page =~ "launch"
  end

  test "json posting returns reply metadata", %{conn: conn} do
    board = board_fixture(%{title: "Technology"})
    thread = thread_fixture(board, %{body: "thread body", subject: "thread subject"})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "thread" => Integer.to_string(thread.id),
        "email" => "noko",
        "body" => "reply body",
        "json_response" => "1",
        "post" => "New Reply"
      })

    thread_id = thread.id

    assert %{"id" => id, "thread_id" => ^thread_id, "redirect" => redirect, "noko" => true} =
             json_response(conn, 200)

    assert redirect == "/#{board.uri}/res/#{thread.id}.html#p#{id}"

    assert Enum.any?(
             get_resp_header(conn, "set-cookie"),
             &String.contains?(&1, "eirinchan_posted=#{board.uri}:#{thread.id}")
           )
  end

  test "posting accepts legacy regist payloads and old field aliases", %{conn: conn} do
    board = board_fixture(%{title: "Technology"})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "name" => "anon",
        "sub" => "launch",
        "com" => "first post",
        "mode" => "regist",
        "json_response" => "1"
      })

    assert %{"id" => thread_id, "thread_id" => thread_id} = json_response(conn, 200)

    conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "resto" => Integer.to_string(thread_id),
        "message" => "legacy reply",
        "mode" => "regist",
        "json_response" => "1"
      })

    assert %{"thread_id" => ^thread_id} = json_response(conn, 200)
  end

  test "successful OP posts set a draft-clear cookie", %{conn: conn} do
    board = board_fixture(%{title: "Technology"})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "name" => "anon",
        "subject" => "launch",
        "body" => "first post",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => _id} = json_response(conn, 200)

    assert Enum.any?(
             get_resp_header(conn, "set-cookie"),
             &String.contains?(&1, "eirinchan_posted=#{board.uri}:new")
           )
  end

  test "posting stores uploads and serves them back under board src paths", %{conn: conn} do
    board = board_fixture()
    upload = upload_fixture("served.png", "served-image")

    create_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file" => upload,
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => id} = json_response(create_conn, 200)

    {:ok, [thread | _]} = Eirinchan.Posts.get_thread(board, id)
    stored_bytes = thread.file_path |> Eirinchan.Uploads.filesystem_path() |> File.read!()

    page =
      conn
      |> recycle()
      |> get("/#{board.uri}")
      |> html_response(200)

    assert page =~ "/#{board.uri}/thumb/#{id}s.png"

    file_conn =
      conn
      |> recycle()
      |> get("/#{board.uri}/src/#{id}.png")

    assert response(file_conn, 200) == stored_bytes
    assert get_resp_header(file_conn, "content-type") == ["image/png; charset=utf-8"]

    thumb_conn =
      conn
      |> recycle()
      |> get("/#{board.uri}/thumb/#{id}s.png")

    assert response(thumb_conn, 200) != ""
    assert get_resp_header(thumb_conn, "content-type") == ["image/png; charset=utf-8"]
  end

  test "posting accepts YouTube embeds and renders the lazy embed block", %{conn: conn} do
    board = board_fixture()

    create_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "embed body",
        "embed" => "https://youtu.be/dQw4w9WgXcQ",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => id, "thread_id" => id} = json_response(create_conn, 200)

    page =
      conn
      |> recycle()
      |> get("/#{board.uri}")
      |> html_response(200)

    assert page =~ ~s(class="video-container")
    assert page =~ "img.youtube.com/vi/dQw4w9WgXcQ/0.jpg"
  end

  test "posting rejects invalid embed urls", %{conn: conn} do
    board = board_fixture()

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "embed body",
        "embed" => "https://example.com/not-youtube",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => error, "error_code" => "invalid_embed"} = json_response(conn, 422)
    assert error =~ "Couldn't make sense"
  end

  test "posting serves allowed non-image uploads with placeholder thumbs", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{allowed_ext_files: [".png", ".jpg", ".jpeg", ".gif", ".txt"]}
      })

    create_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file" => raw_upload_fixture("notes.txt", "hello"),
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => id} = json_response(create_conn, 200)

    page =
      conn
      |> recycle()
      |> get("/#{board.uri}")
      |> html_response(200)

    assert page =~ "/#{board.uri}/thumb/#{id}s.png"

    file_conn =
      conn
      |> recycle()
      |> get("/#{board.uri}/src/#{id}.txt")

    assert response(file_conn, 200) == "hello"
    assert get_resp_header(file_conn, "content-type") == ["text/plain; charset=utf-8"]

    thumb_conn =
      conn
      |> recycle()
      |> get("/#{board.uri}/thumb/#{id}s.png")

    assert response(thumb_conn, 200) != ""
    assert get_resp_header(thumb_conn, "content-type") == ["image/png; charset=utf-8"]
  end

  test "posting accepts multi-file uploads and renders extra file thumbs", %{conn: conn} do
    board = board_fixture()

    create_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "files" => [
          upload_fixture("first.png", "first"),
          upload_fixture("second.gif", "second")
        ],
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => id} = json_response(create_conn, 200)

    page =
      conn
      |> recycle()
      |> get("/#{board.uri}")
      |> html_response(200)

    assert page =~ "/#{board.uri}/thumb/#{id}s.png"
    assert page =~ "/#{board.uri}/thumb/#{id}-1s.png"

    thread_json =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/res/#{id}")
      |> json_response(200)

    assert [op | _] = thread_json["posts"]
    assert length(op["extra_files"]) == 1
  end

  test "posting accepts spoiler uploads and exposes spoiler metadata", %{conn: conn} do
    board = board_fixture()

    create_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "files" => [
          upload_fixture("first.png", "first"),
          upload_fixture("second.gif", "second")
        ],
        "spoiler" => "1",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => id} = json_response(create_conn, 200)

    page =
      conn
      |> recycle()
      |> get("/#{board.uri}")
      |> html_response(200)

    assert page =~ "/#{board.uri}/thumb/#{id}s.png"
    assert page =~ "/#{board.uri}/thumb/#{id}-1s.png"

    thread_json =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/res/#{id}")
      |> json_response(200)

    assert [op | _] = thread_json["posts"]
    assert op["spoiler"] == 1
    assert hd(op["extra_files"])["spoiler"] == 1
  end

  test "posting applies OP-specific extension allowlists", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{allowed_ext_files: [".png", ".jpg"], allowed_ext_files_op: [".txt"]}
      })

    op_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file" => raw_upload_fixture("notes.txt", "hello"),
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => thread_id} = json_response(op_conn, 200)

    reply_conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "thread" => Integer.to_string(thread_id),
        "body" => "reply body",
        "file" => raw_upload_fixture("reply.txt", "hello"),
        "json_response" => "1",
        "post" => "New Reply"
      })

    assert %{"error" => "File type not allowed."} = json_response(reply_conn, 422)
  end

  test "posting rejects extension-spoofed non-image uploads", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{allowed_ext_files: [".png", ".jpg", ".jpeg", ".gif", ".txt"]}
      })

    spoofed_upload =
      duplicate_upload_fixture(upload_fixture("real.png", "png-bytes"), "notes.txt")

    response_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file" => spoofed_upload,
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "File type not allowed."} = json_response(response_conn, 422)
  end

  test "posting fetches remote uploads from file_url when enabled", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{upload_by_url_enabled: true}})
    source_upload = upload_fixture("remote.png", "remote-image")
    server = serve_upload_fixture(File.read!(source_upload.path), "remote.png")
    on_exit(server.stop)

    response_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file_url" => server.url,
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => id} = json_response(response_conn, 200)

    page =
      conn
      |> recycle()
      |> get("/#{board.uri}")
      |> html_response(200)

    assert page =~ "/#{board.uri}/thumb/#{id}s.png"
  end

  test "posting times out remote uploads according to config", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{upload_by_url_enabled: true, upload_by_url_timeout_ms: 50}
      })

    server = serve_stalled_upload("slow.png", delay_ms: 250)
    on_exit(server.stop)

    response_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file_url" => server.url,
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "Upload failed."} = json_response(response_conn, 500)
  end

  test "posting enforces required image uploads and file validation errors", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{force_image_op: true}})

    missing_file =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "File required."} = json_response(missing_file, 422)

    bad_type =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file" => upload_fixture("bad.txt", "bad"),
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "File type not allowed."} = json_response(bad_type, 422)

    invalid_image =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file" => raw_upload_fixture("fake.png", "not-an-image"),
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "Invalid image."} = json_response(invalid_image, 422)
  end

  test "posting enforces image dimension limits", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{max_image_width: 8, max_image_height: 8}})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file" => upload_fixture("wide.png", geometry: "12x9"),
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "Image dimensions too large."} = json_response(conn, 422)
  end

  test "posting enforces image hard limits for file replies", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{image_hard_limit: 1}})

    thread_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file" => upload_fixture("thread.png", "thread"),
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => thread_id} = json_response(thread_conn, 200)

    reply_conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "thread" => Integer.to_string(thread_id),
        "body" => "reply body",
        "file" => upload_fixture("reply.png", "reply"),
        "json_response" => "1",
        "post" => "New Reply"
      })

    assert %{"error" => "Thread has reached its maximum image limit."} =
             json_response(reply_conn, 422)
  end

  test "posting enforces split multi-file size limits", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{max_filesize: 150, multiimage_method: "split"}})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "files" => [
          upload_fixture("first.png", content: "first", geometry: "64x64"),
          upload_fixture("second.png", content: "second", geometry: "64x64")
        ],
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "File too large."} = json_response(conn, 422)
  end

  test "posting rejects duplicate files when global duplicate mode is enabled", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{duplicate_file_mode: "global"}})
    upload = upload_fixture("first.png", "same-bytes")
    duplicate_upload = duplicate_upload_fixture(upload, "second.png")

    first_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "file" => upload,
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => _id} = json_response(first_conn, 200)

    duplicate_conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "second post",
        "file" => duplicate_upload,
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "Duplicate file."} = json_response(duplicate_conn, 422)
  end

  test "noko redirects use canonical slug thread paths when slugify is enabled", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{slugify: true}})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "email" => "noko",
        "subject" => "Slug redirect subject",
        "body" => "first post",
        "post" => "New Topic"
      })

    thread_path = redirected_to(conn)
    assert thread_path =~ "-slug-redirect-subject.html"
    assert conn |> recycle() |> get(thread_path) |> html_response(200) =~ "first post"
  end

  test "posting rejects replies to unknown threads", %{conn: conn} do
    board = board_fixture(%{title: "Technology"})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "thread" => "999999",
        "body" => "reply body",
        "json_response" => "1",
        "post" => "New Reply"
      })

    assert %{"error" => "Thread not found"} = json_response(conn, 404)
  end

  test "posting rejects invalid referers and locked boards", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{board_locked: true}})

    locked_response =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "Board is locked."} = json_response(locked_response, 403)

    open_board = board_fixture()

    bad_referer =
      conn
      |> recycle()
      |> put_req_header("referer", "http://invalid.example/nope")
      |> post(~p"/#{open_board.uri}/post", %{
        "body" => "first post",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "Invalid referer."} = json_response(bad_referer, 403)
  end

  test "posting enforces body length and line limits", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{max_body: 5, maximum_lines: 2}})

    too_long =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "123456",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "The body was too long."} = json_response(too_long, 422)

    too_many_lines =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "a\nb\nc",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "Your post contains too many lines!"} = json_response(too_many_lines, 422)
  end

  test "posting rejects invalid user flags", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{user_flag: true, user_flags: %{"sau" => "Sauce", "spc" => "Space"}}
      })

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "user_flag" => "invalid",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "Invalid flag selection."} = json_response(conn, 422)
  end

  test "posting accepts deduplicated multiple user flags", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          user_flag: true,
          multiple_flags: true,
          user_flags: %{"sau" => "Sauce", "spc" => "Space"}
        }
      })

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "user_flag" => "sau, spc, sau",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => thread_id} = json_response(conn, 200)

    thread_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/res/#{thread_id}.html")
      |> html_response(200)

    assert thread_page =~ ~s(title="Sauce")
    assert thread_page =~ ~s(title="Space")
  end

  test "posting auto-injects country flags from connection metadata", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          country_flags: true,
          country_flag_data: %{"187.180.254.75" => %{code: "mx", name: "Mexico"}}
        }
      })

    conn =
      conn
      |> Map.put(:remote_ip, {187, 180, 254, 75})
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => thread_id} = json_response(conn, 200)

    thread_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/res/#{thread_id}.html")
      |> html_response(200)

    assert thread_page =~ ~s(title="Mexico")
  end

  test "posting rejects invalid captcha responses", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          captcha: %{enabled: true, provider: "hcaptcha", expected_response: "ok"}
        }
      })

    log =
      capture_log(fn ->
        conn =
          conn
          |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
          |> post(~p"/#{board.uri}/post", %{
            "body" => "first post",
            "json_response" => "1",
            "post" => "New Topic"
          })

        assert %{
                 "error" => "Captcha validation failed.",
                 "error_code" => "invalid_captcha",
                 "refresh_captcha" => true,
                 "captcha_provider" => "hcaptcha",
                 "captcha_field" => "h-captcha-response",
                 "captcha_refresh_token" => _
               } = json_response(conn, 422)
      end)

    assert log =~ "post.error"
    assert log =~ "reason=invalid_captcha"
  end

  test "posting validates hosted captcha providers over http", %{conn: conn} do
    server = serve_json_response(~s({"success":true}))

    on_exit(fn ->
      server.stop.()
    end)

    board =
      board_fixture(%{
        config_overrides: %{
          captcha: %{
            enabled: true,
            provider: "hcaptcha",
            verify_url: server.url,
            secret: "topsecret"
          }
        }
      })

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "json_response" => "1",
        "post" => "New Topic",
        "h-captcha-response" => "remote-ok"
      })

    assert %{"id" => _id, "thread_id" => _thread_id} = json_response(conn, 200)
  end

  test "posting rejects active banned ips", %{conn: conn} do
    board = board_fixture()

    {:ok, _ban} =
      Eirinchan.Bans.create_ban(%{
        board_id: board.id,
        ip_subnet: "203.0.113.0/24",
        reason: "Spam wave",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

    conn =
      conn
      |> Map.put(:remote_ip, {203, 0, 113, 9})
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "first post",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "You are banned."} = json_response(conn, 403)
  end

  test "post endpoint accepts ban appeals", %{conn: conn} do
    board = board_fixture()

    {:ok, ban} =
      Eirinchan.Bans.create_ban(%{board_id: board.id, ip_subnet: "203.0.113.4", reason: "Spam"})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "appeal_ban_id" => Integer.to_string(ban.id),
        "body" => "Please review",
        "json_response" => "1"
      })

    assert %{"appeal_id" => _id, "status" => "ok"} = json_response(conn, 200)
  end

  test "report branch creates a report and returns thread redirect metadata", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{slugify: true}})
    thread = thread_fixture(board, %{subject: "Reported subject", body: "Thread body"})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "report_post_id" => Integer.to_string(thread.id),
        "reason" => "Spam thread",
        "json_response" => "1"
      })

    assert %{"report_id" => _id, "redirect" => redirect, "status" => "ok"} =
             json_response(conn, 200)

    assert redirect =~ "/#{board.uri}/res/#{thread.id}-reported-subject.html"
  end

  test "report branch rejects unknown posts", %{conn: conn} do
    board = board_fixture()

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "report_post_id" => "999999",
        "reason" => "Spam thread",
        "json_response" => "1"
      })

    assert %{"error" => "Post not found"} = json_response(conn, 404)
  end

  test "delete branch removes replies and returns thread redirect metadata", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{slugify: true}})

    thread =
      thread_fixture(board, %{subject: "Delete target", body: "Thread body", password: "threadpw"})

    reply_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "thread" => Integer.to_string(thread.id),
        "body" => "Reply body",
        "password" => "replypw",
        "json_response" => "1",
        "post" => "New Reply"
      })

    assert %{"id" => reply_id} = json_response(reply_conn, 200)

    delete_conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "delete_post_id" => Integer.to_string(reply_id),
        "password" => "replypw",
        "json_response" => "1"
      })

    assert %{
             "deleted_post_id" => ^reply_id,
             "thread_deleted" => false,
             "redirect" => redirect
           } = json_response(delete_conn, 200)

    assert redirect =~ "/#{board.uri}/res/#{thread.id}-delete-target.html"
  end

  test "delete branch removes threads and redirects to the board", %{conn: conn} do
    board = board_fixture()

    thread =
      thread_fixture(board, %{subject: "Delete thread", body: "Thread body", password: "threadpw"})

    delete_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "delete_post_id" => Integer.to_string(thread.id),
        "password" => "threadpw",
        "json_response" => "1"
      })

    assert %{
             "deleted_post_id" => deleted_post_id,
             "thread_deleted" => true,
             "redirect" => redirect
           } = json_response(delete_conn, 200)

    assert deleted_post_id == thread.id
    assert redirect == "/#{board.uri}"
  end

  test "delete branch rejects incorrect passwords", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board, %{password: "threadpw"})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "delete_post_id" => Integer.to_string(thread.id),
        "password" => "wrong",
        "json_response" => "1"
      })

    assert %{"error" => "Incorrect password."} = json_response(conn, 403)
  end

  test "legacy mode payloads can delete and report posts", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board, %{body: "Thread body", password: "threadpw"})

    report_conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "mode" => "report",
        "delete[]" => [Integer.to_string(thread.id)],
        "reason" => "legacy report"
      })

    assert redirected_to(report_conn) == "/#{board.uri}/res/#{thread.id}.html"
    [report] = Eirinchan.Reports.list_reports(board)
    assert report.post_id == thread.id

    delete_conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "mode" => "delete",
        "delete[]" => [Integer.to_string(thread.id)],
        "pwd" => "threadpw"
      })

    assert redirected_to(delete_conn) == "/#{board.uri}"
    assert {:error, :not_found} = Eirinchan.Posts.get_thread(board, thread.id)
  end

  test "quick post controls legacy report payload reports the selected post", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board, %{body: "Thread body"})

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "delete_#{thread.id}" => "",
        "reason" => "quick report",
        "report" => "Report"
      })

    assert redirected_to(conn) == "/#{board.uri}/res/#{thread.id}.html"
    [report] = Eirinchan.Reports.list_reports(board)
    assert report.post_id == thread.id
  end
end
