defmodule EirinchanWeb.PollControllerTest do
  use EirinchanWeb.ConnCase, async: false
  alias Eirinchan.{Polls, Posts, Repo}
  alias Eirinchan.Polls.Vote

  defp poll_fixture do
    board = board_fixture()

    {:ok, poll, _} =
      Posts.create_post(
        board,
        %{
          "body" => "Before\n/poll \"A question?\" one \"option two\"\nAfter",
          "post" => "New Topic"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{
          remote_ip: {192, 0, 2, 20},
          referer: "http://example.test/#{board.uri}/index.html"
        }
      )

    {board, poll}
  end

  defp json_conn(conn), do: put_req_header(conn, "accept", "application/json")

  test "posting command renders a cache-neutral poll with its scripts and surrounding text", %{
    conn: conn
  } do
    board = board_fixture()

    result =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "body" => "Before\n/poll \"Meaning of life?\" one two three\nAfter",
        "post" => "New Topic",
        "json_response" => "1"
      })

    assert %{"id" => id} = json_response(result, 200)
    html = result |> recycle() |> get("/#{board.uri}/res/#{id}.html") |> html_response(200)
    assert html =~ "Meaning of life?"
    assert html =~ "post-poll"
    assert html =~ "/js/polls.js"
    assert html =~ "/stylesheets/polls.css"
    assert html =~ "Before<br/>"
    assert html =~ "<br/>After"
    refute html =~ "Total votes:"
  end

  test "status is private and never exposes counts for an identity without a receipt", %{
    conn: conn
  } do
    {_board, poll} = poll_fixture()
    assert {:ok, _} = Polls.vote(poll.id, 0, %{remote_ip: {198, 51, 100, 10}})
    response = conn |> json_conn() |> get("/api/polls/state?ids=#{poll.id}")

    assert json_response(response, 200) == %{
             "data" => %{to_string(poll.id) => %{"voted" => false}}
           }

    assert get_resp_header(response, "cache-control") == ["private, no-store"]
    assert "Cookie" in get_resp_header(response, "vary")
  end

  test "vote requires CSRF and returns results only after a successful vote", %{conn: conn} do
    {_board, poll} = poll_fixture()
    denied = conn |> json_conn() |> post("/api/polls/#{poll.id}/vote", %{"choice" => 0})
    assert %{"csrf" => true} = json_response(denied, 403)
    assert get_resp_header(denied, "cache-control") == ["private, no-store"]
    assert Repo.aggregate(Vote, :count) == 0

    csrf_conn = get(recycle(conn), "/csrf-token")
    token = json_response(csrf_conn, 200)["csrf_token"]

    voted =
      csrf_conn
      |> recycle()
      |> json_conn()
      |> put_req_header("x-csrf-token", token)
      |> post("/api/polls/#{poll.id}/vote", %{"choice" => 1})

    assert %{
             "data" => %{
               "voted" => true,
               "total" => 1,
               "results" => [%{"count" => 0}, %{"count" => 1}]
             }
           } = json_response(voted, 200)

    response = voted |> recycle() |> json_conn() |> get("/api/polls/state?ids=#{poll.id}")
    key = to_string(poll.id)
    assert %{"data" => %{^key => %{"voted" => true, "total" => 1}}} = json_response(response, 200)
  end

  test "malformed and excessive batches are rejected without SQL errors", %{conn: conn} do
    for ids <- ["0", "-1", "123x", String.duplicate("9", 2000), Enum.join(1..51, ","), "1,,2"] do
      response = conn |> recycle() |> json_conn() |> get("/api/polls/state", %{"ids" => ids})
      assert %{"error" => _} = json_response(response, 400)
    end
  end

  test "malformed poll posts return readable validation errors and no post", %{conn: conn} do
    board = board_fixture()

    response =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "body" => "/poll Q a b c d e f g",
        "post" => "New Topic",
        "json_response" => "1"
      })

    assert %{"error_code" => "invalid_poll", "error" => message} = json_response(response, 422)
    assert message =~ "2–6"
    assert Repo.aggregate(Vote, :count) == 0
  end

  test "missing, huge and out-of-range choices cannot cast a vote", %{conn: conn} do
    {_board, poll} = poll_fixture()
    csrf_conn = get(conn, "/csrf-token")
    token = json_response(csrf_conn, 200)["csrf_token"]

    for choice <- [-1, 2, 6, %{}, String.duplicate("9", 10000)] do
      response =
        csrf_conn
        |> recycle()
        |> json_conn()
        |> put_req_header("x-csrf-token", token)
        |> post("/api/polls/#{poll.id}/vote", %{"choice" => choice})

      assert %{"error" => _} = json_response(response, 422)
    end

    assert Repo.aggregate(Vote, :count) == 0
  end
end
