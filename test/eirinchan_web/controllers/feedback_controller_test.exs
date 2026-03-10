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
end
