defmodule EirinchanWeb.UploadedFileControllerTest do
  use EirinchanWeb.ConnCase, async: true

  test "thumbnail route sends immutable cache headers for existing thumbs", %{conn: conn} do
    board = board_fixture()
    upload = upload_fixture("thumb-cache.png", "thumb-cache")

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

    conn =
      conn
      |> recycle()
      |> get(thread.thumb_path)

    assert response(conn, 200) != ""
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
  end

  test "source route sends one-month cache headers for existing uploads", %{conn: conn} do
    board = board_fixture()
    upload = upload_fixture("src-cache.png", "src-cache")

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

    conn =
      conn
      |> recycle()
      |> get(thread.file_path)

    assert response(conn, 200) != ""
    assert get_resp_header(conn, "cache-control") == ["public, max-age=2592000"]
  end

  test "source route serves byte ranges for existing uploads", %{conn: conn} do
    board = board_fixture()
    upload = upload_fixture("range-cache.png", "range-cache")

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
    path = Eirinchan.Uploads.filesystem_path(thread.file_path)
    size = File.stat!(path).size

    conn =
      conn
      |> recycle()
      |> put_req_header("range", "bytes=0-31")
      |> get(thread.file_path)

    assert response(conn, 206) != ""
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "content-range") == ["bytes 0-31/#{size}"]
  end

  test "source route rejects invalid byte ranges", %{conn: conn} do
    board = board_fixture()
    upload = upload_fixture("invalid-range.png", "invalid-range")

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

    path = Eirinchan.Uploads.filesystem_path(thread.file_path)
    size = File.stat!(path).size

    conn =
      conn
      |> recycle()
      |> put_req_header("range", "bytes=#{size}-#{size + 100}")
      |> get(thread.file_path)

    assert response(conn, 416) == ""
    assert get_resp_header(conn, "content-range") == ["bytes */#{size}"]
  end

  test "uploaded file route returns not found for missing files", %{conn: conn} do
    board = board_fixture()

    conn = get(conn, "/#{board.uri}/src/missing.png")

    assert response(conn, 404) == "File not found"
  end

  test "thumbnail route returns not found for missing files", %{conn: conn} do
    board = board_fixture()

    conn = get(conn, "/#{board.uri}/thumb/missing.png")

    assert response(conn, 404) == "File not found"
  end
end
