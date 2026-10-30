defmodule EirinchanWeb.PostFeedbackControllerTest do
  use EirinchanWeb.ConnCase, async: false
  alias Eirinchan.{Feedback, Repo}
  alias Eirinchan.Posts.Post

  setup %{conn: conn} do
    {:ok, _grant} = Eirinchan.AccessList.record_access("192.0.2.0/24", "synthetic-feedback-grant")
    {:ok, conn: %{conn | remote_ip: {192, 0, 2, 25}}}
  end

  test "unverified commands have the same success receipt but store neither feedback nor a post",
       %{conn: conn} do
    board = board_fixture()

    result =
      %{conn | remote_ip: {203, 0, 113, 25}}
      |> post("/#{board.uri}/post", %{
        "body" => "/feedback Silently discarded",
        "json_response" => "1"
      })

    assert json_response(result, 200) == %{"status" => "ok", "feedback_submitted" => true}
    assert Feedback.list_feedback() == []
    assert Repo.aggregate(Post, :count) == 0
  end

  test "classic unverified commands get the normal confirmation without storage", %{conn: conn} do
    board = board_fixture()

    result =
      %{conn | remote_ip: {203, 0, 113, 25}}
      |> post("/#{board.uri}/post", %{"body" => "/feedback Silently discarded"})

    assert html_response(result, 200) =~ "Feedback submitted!"
    assert Feedback.list_feedback() == []
    assert Repo.aggregate(Post, :count) == 0
  end

  test "an expired IPv6 grant is rejected, while a fresh matching subnet is accepted", %{
    conn: conn
  } do
    board = board_fixture()
    ip = {0x2001, 0xDB8, 7, 0, 0, 0, 0, 9}

    {:ok, _} =
      Eirinchan.AccessList.record_access("2001:db8:7::/48", "synthetic-expired",
        granted_at: NaiveDateTime.add(NaiveDateTime.local_now(), -200 * 3600, :second)
      )

    params = %{"body" => "/feedback IPv6 feedback", "json_response" => "1"}

    assert %{conn | remote_ip: ip} |> post("/#{board.uri}/post", params) |> json_response(200) ==
             %{"status" => "ok", "feedback_submitted" => true}

    assert Feedback.list_feedback() == []
    {:ok, _} = Eirinchan.AccessList.record_access("2001:db8:7::/48", "synthetic-fresh")

    assert %{conn | remote_ip: ip} |> post("/#{board.uri}/post", params) |> json_response(200) ==
             %{"status" => "ok", "feedback_submitted" => true}

    assert [%{body: "IPv6 feedback"}] = Feedback.list_feedback()
    assert Repo.aggregate(Post, :count) == 0
  end

  test "new-topic commands create feedback only and preserve supplied contact fields", %{
    conn: conn
  } do
    board = board_fixture()

    conn =
      post(conn, "/#{board.uri}/post", %{
        "body" => "/feedback A useful suggestion",
        "name" => "Alice##synthetic-secret",
        "email" => "alice@example.invalid",
        "json_response" => "1",
        "file_url" => "https://example.invalid/unused.png",
        "read_at" => "2020-01-01T00:00:00Z"
      })

    assert json_response(conn, 200) == %{"status" => "ok", "feedback_submitted" => true}
    assert [entry] = Feedback.list_feedback()
    assert entry.body == "A useful suggestion"
    assert entry.name == "Alice"
    assert entry.email == "alice@example.invalid"
    assert entry.read_at == nil
    assert Repo.aggregate(Post, :count) == 0

    assert conn.resp_cookies
           |> Map.keys()
           |> Enum.all?(&(not String.starts_with?(&1, "eirinchan_posted_")))
  end

  test "reply commands never add a reply or affect thread counters", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    before = Repo.get!(Post, thread.id)

    result =
      post(conn, "/#{board.uri}/post", %{
        "thread" => to_string(thread.public_id),
        "body" => "/feedback Reply form suggestion",
        "json_response" => "1"
      })

    assert %{"feedback_submitted" => true} = json_response(result, 200)
    assert Repo.aggregate(Post, :count) == 1
    assert Repo.get!(Post, thread.id) == before
    assert [%{body: "Reply form suggestion"}] = Feedback.list_feedback()
  end

  test "command feedback is capped at 2000 characters independently of posting limits", %{
    conn: conn
  } do
    board = board_fixture(%{config_overrides: %{max_body: 10}})

    result =
      post(conn, "/#{board.uri}/post", %{
        "body" => "/feedback " <> String.duplicate("界", 2_001),
        "json_response" => "1"
      })

    assert %{"feedback_submitted" => true} = json_response(result, 200)
    assert [entry] = Feedback.list_feedback()
    assert entry.body == String.duplicate("界", 2_000)
    assert Repo.aggregate(Post, :count) == 0
  end

  test "empty commands validate as feedback and never fall back to publishing a post", %{
    conn: conn
  } do
    board = board_fixture()
    result = post(conn, "/#{board.uri}/post", %{"body" => "/feedback", "json_response" => "1"})
    assert json_response(result, 422)["error"]
    assert Feedback.list_feedback() == []
    assert Repo.aggregate(Post, :count) == 0
  end

  test "a non-command body still creates a normal public post", %{conn: conn} do
    board = board_fixture()

    conn = put_req_header(conn, "referer", "http://www.example.com/#{board.uri}/index.html")

    result =
      post(conn, "/#{board.uri}/post", %{
        "body" => "/feedbackish ordinary post",
        "post" => "New Topic",
        "json_response" => "1"
      })

    assert %{"id" => _id} = json_response(result, 200)
    assert Feedback.list_feedback() == []
    assert Repo.aggregate(Post, :count) == 1
  end

  test "legacy posting commands use the same admission and never publish", %{conn: conn} do
    board = board_fixture()

    result =
      post(conn, "/post.php", %{
        "board" => board.uri,
        "body" => "/feedback Legacy feedback",
        "json_response" => "1"
      })

    assert json_response(result, 200) == %{"status" => "ok", "feedback_submitted" => true}
    assert [%{body: "Legacy feedback"}] = Feedback.list_feedback()
    assert Repo.aggregate(Post, :count) == 0
  end

  test "classic form commands have a CSP-safe confirmation document", %{conn: conn} do
    board = board_fixture()
    result = post(conn, "/#{board.uri}/post", %{"body" => "/feedback Useful classic feedback"})
    html = html_response(result, 200)
    assert html =~ "Feedback submitted!"
    assert html =~ "/js/feedback-submitted.js"
    assert html =~ ~s(href="/#{board.uri}")
    refute html =~ "alert("
    assert Repo.aggregate(Post, :count) == 0
  end

  test "command and feedback form share the global feedback submission budget", %{conn: conn} do
    previous = Application.get_env(:eirinchan, :feedback_overrides, %{})

    Application.put_env(:eirinchan, :feedback_overrides, %{
      feedback_submissions_per_minutes: [1, 2],
      feedback_submissions_per_minutes_all: [0, 2]
    })

    on_exit(fn -> Application.put_env(:eirinchan, :feedback_overrides, previous) end)
    board = board_fixture()

    assert %{"status" => "ok"} =
             conn
             |> post("/feedback", %{"body" => "First feedback", "json_response" => "1"})
             |> json_response(200)

    rejected =
      conn
      |> recycle()
      |> post("/#{board.uri}/post", %{
        "body" => "/feedback Second feedback",
        "json_response" => "1"
      })

    assert json_response(rejected, 429)["error"] =~ "Feedback is limited"
    assert length(Feedback.list_feedback()) == 1
    assert Repo.aggregate(Post, :count) == 0
  end

  test "API commands retain CSRF validation and the same feedback-only response", %{conn: conn} do
    board = board_fixture()
    params = %{"board" => board.uri, "body" => "/feedback API feedback"}
    denied = conn |> put_req_header("accept", "application/json") |> post("/api/post", params)
    assert response(denied, 403)
    assert Feedback.list_feedback() == []
    token_conn = get(conn, "/csrf-token")
    token = json_response(token_conn, 200)["csrf_token"]

    accepted =
      token_conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-csrf-token", token)
      |> post("/api/post", params)

    assert json_response(accepted, 200) == %{"status" => "ok", "feedback_submitted" => true}
    assert Repo.aggregate(Post, :count) == 0
  end
end
