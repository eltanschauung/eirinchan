defmodule EirinchanWeb.BoardControllerTest do
  use EirinchanWeb.ConnCase, async: false

  test "board index returns an etag and honors if-none-match", %{conn: conn} do
    board = board_fixture()
    _thread = thread_fixture(board, %{body: "Thread body", subject: "Thread subject"})

    first_conn = get(conn, "/#{board.uri}")
    assert first_conn.status == 200

    etag =
      first_conn
      |> get_resp_header("etag")
      |> List.first()

    assert is_binary(etag)
    assert get_resp_header(first_conn, "cache-control") == ["private, no-cache"]

    second_conn =
      conn
      |> recycle()
      |> put_req_header("if-none-match", etag)
      |> get("/#{board.uri}")

    assert second_conn.status == 304
    assert second_conn.resp_body == ""
    assert get_resp_header(second_conn, "etag") == [etag]
  end

  test "board index keeps the shared postcontrols form outside the thread tree", %{conn: conn} do
    board = board_fixture()
    _thread = thread_fixture(board, %{body: "Thread body", subject: "Thread subject"})

    page = get(conn, "/#{board.uri}") |> html_response(200)

    assert page =~ ~s(<div id="board-threads">)
    assert page =~ ~s(<form name="postcontrols" action="/post.php" method="post">)
    assert page =~ ~s(name="delete_post_id")
    assert page =~ ~s(name="report_post_id")

    {threads_pos, _} = :binary.match(page, ~s(<div id="board-threads">))
    {form_pos, _} = :binary.match(page, ~s(<form name="postcontrols" action="/post.php" method="post">))

    assert threads_pos < form_pos
  end
end
