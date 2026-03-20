defmodule EirinchanWeb.FeedbackControllerTest do
  use EirinchanWeb.ConnCase, async: true

  test "public feedback page renders and accepts submissions", %{conn: conn} do
    board_fixture(%{uri: "tech", title: "Technology"})

    page = conn |> get("/feedback") |> html_response(200)

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

  test "feedback submission validates body", %{conn: conn} do
    conn =
      conn
      |> post("/feedback", %{"body" => "   ", "json_response" => "1"})

    assert %{"errors" => %{"body" => [_ | _]}} = json_response(conn, 422)
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

    assert %{"error" => "Wait a while before searching again, please."} =
             json_response(second_conn, 429)
  end

  test "feedback page renders global message placeholders and line breaks", %{conn: conn} do
    board = board_fixture(%{uri: "feedbackgm#{System.unique_integer([:positive])}", title: "Feedback GM"})
    thread = thread_fixture(board, %{body: "seed"})
    reply_fixture(board, thread, %{body: "recent"})

    :ok =
      Eirinchan.Settings.persist_instance_config(%{
        global_message:
          "Visitors in the last 10 minutes: {stats.users_10minutes}\\nPPH: {stats.posts_perhour}"
      })

    page = conn |> get("/feedback") |> html_response(200)

    assert page =~ "Visitors in the last 10 minutes:"
    assert page =~ "PPH:"
    assert page =~ "<br />"
    refute page =~ "{stats.users_10minutes}"
    refute page =~ "{stats.posts_perhour}"
  end
end
