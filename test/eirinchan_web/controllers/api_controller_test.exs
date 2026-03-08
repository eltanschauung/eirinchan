defmodule EirinchanWeb.ApiControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.Posts

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-api-themes-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    :ok
  end

  test "board api endpoints expose page, catalog, threads, and thread json", %{conn: conn} do
    :ok = Eirinchan.Themes.enable_page_theme("catalog")
    board = board_fixture(%{config_overrides: %{threads_per_page: 1, threads_preview: 1}})
    upload = upload_fixture("thread.png", "thread")

    thread =
      thread_fixture(board, %{
        body: "Thread body",
        subject: "Thread subject",
        file: upload
      })

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
      "body" => "Second thread body",
      "subject" => "Second thread",
      "post" => "New Topic"
    })

    page_json =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/pages/0")
      |> json_response(200)

    catalog_json =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/catalog.json")
      |> json_response(200)

    threads_json =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/threads.json")
      |> json_response(200)

    thread_json =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/res/#{thread.id}")
      |> json_response(200)

    boards_json =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/boards.json")
      |> json_response(200)

    assert length(page_json["threads"]) == 1
    assert length(catalog_json) == 2
    assert Enum.all?(threads_json, &Map.has_key?(&1, "threads"))
    assert [op | replies] = thread_json["posts"]
    assert op["resto"] == 0
    assert op["filename"] == "thread"
    assert op["ext"] == ".png"
    assert op["fsize"] == thread.file_size
    assert is_binary(op["md5"])
    assert op["w"] == 16
    assert op["h"] == 16
    assert length(replies) == 1

    assert Enum.any?(
             boards_json["boards"],
             &(&1["board"] == board.uri and &1["title"] == board.title)
           )
  end

  test "thread api exposes moderation state flags on OP posts", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)

    conn =
      conn
      |> login_moderator(moderator_fixture())
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{board.uri}/threads/#{thread.id}", %{
        "sticky" => "true",
        "locked" => "true",
        "cycle" => "true",
        "sage" => "true"
      })

    assert %{"data" => %{"sticky" => true}} = json_response(conn, 200)

    thread_json =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/res/#{thread.id}")
      |> json_response(200)

    assert [op | _] = thread_json["posts"]
    assert op["sticky"] == 1
    assert op["closed"] == 1
    assert op["cyclical"] == 1
    assert op["bumplimit"] == 1
  end

  test "thread api omits image dimensions for non-image uploads", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{allowed_ext_files: [".png", ".jpg", ".jpeg", ".gif", ".txt"]}
      })

    thread =
      thread_fixture(board, %{
        body: "Thread body",
        subject: "Thread subject",
        file: raw_upload_fixture("notes.txt", "hello")
      })

    thread_json =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/res/#{thread.id}")
      |> json_response(200)

    assert [op | _] = thread_json["posts"]
    assert op["ext"] == ".txt"
    refute Map.has_key?(op, "w")
    refute Map.has_key?(op, "h")
  end

  test "thread api exposes extra_files for multi-file posts", %{conn: conn} do
    board = board_fixture()

    thread =
      thread_fixture(board, %{
        body: "Thread body",
        subject: "Thread subject",
        files: [
          upload_fixture("first.png", "first"),
          upload_fixture("second.gif", "second")
        ]
      })

    thread_json =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/res/#{thread.id}")
      |> json_response(200)

    assert [op | _] = thread_json["posts"]
    assert length(op["extra_files"]) == 1
    assert hd(op["extra_files"])["ext"] == ".gif"
  end

  test "thread api exposes spoiler flags for primary and extra files", %{conn: conn} do
    board = board_fixture()

    thread =
      thread_fixture(board, %{
        body: "Thread body",
        subject: "Thread subject",
        files: [
          upload_fixture("first.png", "first"),
          upload_fixture("second.gif", "second")
        ],
        spoiler: "1"
      })

    thread_json =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/res/#{thread.id}")
      |> json_response(200)

    assert [op | _] = thread_json["posts"]
    assert op["spoiler"] == 1
    assert hd(op["extra_files"])["spoiler"] == 1
  end

  test "thread api exposes country fields and a stable poster id", %{conn: conn} do
    board = board_fixture(%{config_overrides: %{country_flags: true}})

    {:ok, thread, _meta} =
      Posts.create_post(
        board,
        %{"body" => "Country body", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{
          referer: "http://www.example.com/#{board.uri}/index.html",
          remote_ip: {198, 51, 100, 22},
          country_code: "us",
          country_name: "United States"
        }
      )

    thread_json =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/#{board.uri}/res/#{thread.id}")
      |> json_response(200)

    expected_id =
      :crypto.hash(:sha256, "#{board.id}:198.51.100.22")
      |> Base.encode16(case: :upper)
      |> binary_part(0, 8)

    assert [op | _] = thread_json["posts"]
    assert op["country"] == "US"
    assert op["country_name"] == "United States"
    assert op["id"] == expected_id
  end
end
