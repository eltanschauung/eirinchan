defmodule EirinchanWeb.FeedbackManagementControllerTest do
  use EirinchanWeb.ConnCase, async: true

  test "feedback queue lists entries, marks read, adds notes, and deletes", %{conn: conn} do
    moderator = moderator_fixture()

    conn =
      conn
      |> post("/feedback", %{"body" => "Needs review", "json_response" => "1"})

    assert %{"feedback_id" => feedback_id} = json_response(conn, 200)

    queue_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_req_header("accept", "application/json")

    assert %{
             "data" => [%{"id" => ^feedback_id, "body" => "Needs review", "read_at" => nil}],
             "unread_count" => 1,
             "actions" => actions
           } =
             queue_conn
             |> get("/manage/feedback")
             |> json_response(200)

    assert Enum.map(actions, & &1["label"]) == ["Mark as Read", "Add Note", "Delete"]

    assert %{"data" => %{"id" => ^feedback_id, "read_at" => read_at}, "actions" => _actions} =
             queue_conn
             |> recycle()
             |> login_moderator(moderator)
             |> put_secure_manage_token()
             |> put_req_header("accept", "application/json")
             |> patch("/manage/feedback/#{feedback_id}/read", %{})
             |> json_response(200)

    assert read_at

    assert %{"data" => %{"comments" => [%{"body" => "Admin note"}]}, "actions" => _actions} =
             queue_conn
             |> recycle()
             |> login_moderator(moderator)
             |> put_secure_manage_token()
             |> put_req_header("accept", "application/json")
             |> post("/manage/feedback/#{feedback_id}/comments", %{"body" => "Admin note"})
             |> json_response(200)

    assert response(
             queue_conn
             |> recycle()
             |> login_moderator(moderator)
             |> put_secure_manage_token()
             |> put_req_header("accept", "application/json")
             |> delete("/manage/feedback/#{feedback_id}"),
             204
           )

    assert %{"data" => []} =
             queue_conn
             |> recycle()
             |> login_moderator(moderator)
             |> put_req_header("accept", "application/json")
             |> get("/manage/feedback")
             |> json_response(200)
  end

  test "non-admin moderators do not receive feedback ip values", %{conn: conn} do
    moderator = moderator_fixture(%{role: "mod"})

    conn =
      conn
      |> Map.put(:remote_ip, {198, 51, 100, 9})
      |> post("/feedback", %{"body" => "Needs review", "json_response" => "1"})

    assert %{"feedback_id" => _feedback_id} = json_response(conn, 200)

    assert %{"data" => [%{"ip_subnet" => nil}]} =
             conn
             |> recycle()
             |> login_moderator(moderator)
             |> put_req_header("accept", "application/json")
             |> get("/manage/feedback")
             |> json_response(200)
  end
end
