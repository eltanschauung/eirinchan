defmodule EirinchanWeb.ModDashboardControllerTest do
  use EirinchanWeb.ConnCase, async: true

  alias Eirinchan.Posts.PublicIds

  test "dashboard reports accessible board/report counts and unread feedback", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(board)

    conn
    |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
    |> post("/#{board.uri}/post", %{
      "report_post_id" => Integer.to_string(thread.id),
      "reason" => "Spam",
      "json_response" => "1"
    })
    |> json_response(200)

    conn
    |> recycle()
    |> post("/feedback", %{"body" => "Needs review", "json_response" => "1"})
    |> json_response(200)

    assert %{
             "data" => %{
               "board_count" => 1,
               "report_count" => 1,
               "feedback_unread_count" => 1,
               "boards" => [%{"uri" => uri}]
             }
           } =
             conn
             |> recycle()
             |> login_moderator(moderator)
             |> put_req_header("accept", "application/json")
             |> get("/manage/dashboard")
             |> json_response(200)

    assert uri == board.uri
  end

  test "recent posts lists newest posts for accessible boards only", %{conn: conn} do
    board = board_fixture()
    other_board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(board)

    _older = thread_fixture(board, %{body: "older"})
    newer = reply_fixture(board, thread_fixture(board), %{body: "newer"})
    _other = thread_fixture(other_board, %{body: "other"})

    assert %{"data" => posts} =
             conn
             |> login_moderator(moderator)
             |> put_req_header("accept", "application/json")
             |> get("/manage/recent-posts", %{"limit" => "5"})
             |> json_response(200)

    assert Enum.any?(posts, &(&1["id"] == PublicIds.public_id(newer)))
    refute Enum.any?(posts, &(&1["board_id"] == other_board.id))
  end

  test "recent posts defaults malformed limits instead of raising", %{conn: conn} do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(board)
    _thread = thread_fixture(board)

    assert %{"data" => [_post]} =
             conn
             |> login_moderator(moderator)
             |> put_req_header("accept", "application/json")
             |> get("/manage/recent-posts", %{"limit" => "not-a-number"})
             |> json_response(200)
  end
end
