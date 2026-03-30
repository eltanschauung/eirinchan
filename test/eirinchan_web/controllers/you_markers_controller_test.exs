defmodule EirinchanWeb.YouMarkersControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.PostOwnership
  alias Eirinchan.Posts.PublicIds

  test "api returns owned public post ids for the current browser token", %{conn: conn} do
    board = board_fixture(%{uri: "showyousapi", title: "Show Yous API"})
    thread = thread_fixture(board, %{body: "Opening body"})
    reply = reply_fixture(board, thread, %{body: "Reply body"})
    token = "show-yous-api-token"

    assert {:ok, _} = PostOwnership.record(token, thread.id)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_cookie("show_yous", "true")
      |> put_req_header("content-type", "application/json")
      |> post("/api/you-markers/#{board.uri}", %{post_ids: [PublicIds.public_id(thread), PublicIds.public_id(reply)]})

    assert %{"enabled" => true, "post_ids" => [owned_id]} = json_response(conn, 200)
    assert owned_id == PublicIds.public_id(thread)
  end

  test "api returns no ids when show yous is disabled", %{conn: conn} do
    board = board_fixture(%{uri: "showyousoff", title: "Show Yous Off"})
    thread = thread_fixture(board, %{body: "Opening body"})
    token = "show-yous-disabled-token"

    assert {:ok, _} = PostOwnership.record(token, thread.id)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_cookie("show_yous", "false")
      |> put_req_header("content-type", "application/json")
      |> post("/api/you-markers/#{board.uri}", %{post_ids: [PublicIds.public_id(thread)]})

    assert %{"enabled" => false, "post_ids" => []} = json_response(conn, 200)
  end
end
