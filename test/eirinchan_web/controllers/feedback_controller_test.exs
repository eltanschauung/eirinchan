defmodule EirinchanWeb.FeedbackControllerTest do
  use EirinchanWeb.ConnCase, async: false
  import ExUnit.CaptureLog

  test "public feedback page renders and accepts submissions", %{conn: conn} do
    moderator_fixture()
    board_fixture(%{uri: "tech", title: "Technology"})

    page = conn |> get("/feedback") |> html_response(200)

    assert page =~ "Submit any kind of feedback you want."
    assert page =~ "Send Feedback"
    assert page =~ ~s(class="boardlist")
    assert page =~ ~s(class="feedback-textarea")

    conn =
      conn
      |> recycle()
      |> post("/feedback", %{
        "name" => "Anon",
        "body" => "Public feedback",
        "json_response" => "1"
      })

    assert %{"feedback_id" => _id, "status" => "ok"} = json_response(conn, 200)
  end

  test "feedback form is not conditionally cached with a session-bound csrf token", %{conn: conn} do
    response = get(conn, "/feedback")

    assert html_response(response, 200) =~ ~s(name="_csrf_token")
    assert get_resp_header(response, "etag") == []

    assert Enum.any?(
             get_resp_header(response, "cache-control"),
             &String.contains?(&1, "no-store")
           )

    stale_revalidation =
      conn
      |> recycle()
      |> put_req_header("if-none-match", ~s("stale-feedback-document"))
      |> get("/feedback")

    assert html_response(stale_revalidation, 200) =~ ~s(name="_csrf_token")
    assert get_resp_header(stale_revalidation, "etag") == []
  end

  test "feedback submission validates body", %{conn: conn} do
    conn =
      conn
      |> post("/feedback", %{"body" => "   ", "json_response" => "1"})

    assert %{"errors" => %{"body" => [_ | _]}} = json_response(conn, 422)
  end

  test "feedback submission rejects bodies without a space as antispam", %{conn: conn} do
    {conn, log} =
      with_log(fn ->
        conn
        |> post("/feedback", %{"body" => "singleword", "json_response" => "1"})
      end)

    assert %{"error" => "Spam filter triggered."} = json_response(conn, 422)
    assert log =~ ~s|"event":"feedback.rejected"|
    assert log =~ ~s|"outcome":"body_shape"|
    refute log =~ "singleword"
    assert Eirinchan.Feedback.unread_count() == 0
  end

  test "feedback submission uses search-style public rate limits", %{conn: conn} do
    previous = Application.get_env(:eirinchan, :search_overrides, %{})

    Application.put_env(:eirinchan, :search_overrides, %{
      search_queries_per_minutes: [1, 2],
      search_queries_per_minutes_all: [0, 2]
    })

    on_exit(fn ->
      Application.put_env(:eirinchan, :search_overrides, previous)
    end)

    first_conn =
      conn
      |> post("/feedback", %{
        "name" => "Anon",
        "body" => "Public feedback",
        "json_response" => "1"
      })

    assert %{"status" => "ok"} = json_response(first_conn, 200)

    second_conn =
      conn
      |> recycle()
      |> post("/feedback", %{
        "name" => "Anon",
        "body" => "More feedback",
        "json_response" => "1"
      })

    assert %{
             "error" =>
               "Feedback is limited to five submissions per 24 hours. Please try again later."
           } =
             json_response(second_conn, 429)
  end

  test "feedback page displays rate-limit messages without internal field names", %{conn: conn} do
    previous = Application.get_env(:eirinchan, :search_overrides, %{})

    Application.put_env(:eirinchan, :search_overrides, %{
      search_queries_per_minutes: [1, 2],
      search_queries_per_minutes_all: [0, 2]
    })

    on_exit(fn -> Application.put_env(:eirinchan, :search_overrides, previous) end)

    conn
    |> post("/feedback", %{"body" => "First feedback", "json_response" => "1"})
    |> json_response(200)

    page =
      conn
      |> recycle()
      |> post("/feedback", %{"body" => "Second feedback"})
      |> html_response(429)

    assert page =~ "Feedback is limited to five submissions per 24 hours."
    refute page =~ "rate_limit:"
  end

  test "feedback submission is limited to five attempts per IP in 24 hours", %{conn: conn} do
    previous = Application.get_env(:eirinchan, :search_overrides, %{})

    Application.put_env(:eirinchan, :search_overrides, %{
      search_queries_per_minutes: [0, 2],
      search_queries_per_minutes_all: [0, 2]
    })

    on_exit(fn -> Application.put_env(:eirinchan, :search_overrides, previous) end)

    Enum.each(1..5, fn attempt ->
      response =
        conn
        |> recycle()
        |> post("/feedback", %{
          "body" => "Allowed feedback #{attempt}",
          "json_response" => "1"
        })

      assert %{"status" => "ok"} = json_response(response, 200)
    end)

    response =
      conn
      |> recycle()
      |> post("/feedback", %{"body" => "Blocked feedback", "json_response" => "1"})

    assert %{
             "error" =>
               "Feedback is limited to five submissions per 24 hours. Please try again later."
           } =
             json_response(response, 429)
  end

  test "feedback page suppresses the global message and keeps the centered feedback body", %{
    conn: conn
  } do
    moderator_fixture()

    board =
      board_fixture(%{
        uri: "feedbackgm#{System.unique_integer([:positive])}",
        title: "Feedback GM"
      })

    thread = thread_fixture(board, %{body: "seed"})
    reply_fixture(board, thread, %{body: "recent"})

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        global_message:
          "Visitors in the last 10 minutes: {stats.users_10minutes}\\nPPH: {stats.posts_perhour}"
      })

    page = conn |> get("/feedback") |> html_response(200)

    refute page =~ "Visitors in the last 10 minutes:"
    refute page =~ "PPH:"
    refute page =~ "{stats.users_10minutes}"
    refute page =~ "{stats.posts_perhour}"
    assert page =~ "feedback-copy"
    assert page =~ "Submit any kind of feedback you want."
  end
end
