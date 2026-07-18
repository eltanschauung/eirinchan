defmodule EirinchanWeb.YouMarkersControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.PostOwnership
  alias Eirinchan.Posts.PublicIds

  test "api returns owned public post ids for the current browser token", %{conn: conn} do
    board = board_fixture(%{uri: "showyousapi", title: "Show Yous API"})
    thread = thread_fixture(board, %{body: "Opening body"})
    reply = reply_fixture(board, thread, %{body: "Reply body"})
    token = browser_token("show-yous-api")

    assert {:ok, _} = PostOwnership.record(token, thread.id)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_cookie("show_yous", "true")
      |> put_req_header("content-type", "application/json")
      |> post("/api/you-markers/#{board.uri}", %{
        post_ids: [PublicIds.public_id(thread), PublicIds.public_id(reply)]
      })

    assert %{"enabled" => true, "post_ids" => [owned_id]} = json_response(conn, 200)
    assert owned_id == PublicIds.public_id(thread)
  end

  test "api returns no ids when show yous is disabled", %{conn: conn} do
    board = board_fixture(%{uri: "showyousoff", title: "Show Yous Off"})
    thread = thread_fixture(board, %{body: "Opening body"})
    token = browser_token("show-yous-disabled")

    assert {:ok, _} = PostOwnership.record(token, thread.id)

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_cookie("show_yous", "false")
      |> put_req_header("content-type", "application/json")
      |> post("/api/you-markers/#{board.uri}", %{post_ids: [PublicIds.public_id(thread)]})

    assert %{"enabled" => false, "post_ids" => []} = json_response(conn, 200)
  end

  test "api bounds oversized ownership lookups", %{conn: conn} do
    board = board_fixture(%{uri: "showyousbound", title: "Bounded Yous"})
    token = browser_token("show-yous-bounded")

    conn =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_cookie("show_yous", "true")
      |> put_req_header("content-type", "application/json")
      |> post("/api/you-markers/#{board.uri}", %{post_ids: Enum.to_list(1..10_000)})

    assert %{"enabled" => true, "post_ids" => []} = json_response(conn, 200)
  end

  test "api honors the configured ownership lookup bound", %{conn: conn} do
    board = board_fixture(%{uri: "showyousconfigured", title: "Configured Yous"})
    thread = thread_fixture(board, %{body: "Opening body"})
    first = reply_fixture(board, thread, %{body: "First reply"})
    second = reply_fixture(board, thread, %{body: "Second reply"})
    token = browser_token("show-yous-configured")

    for post <- [thread, first, second] do
      assert {:ok, _ownership} = PostOwnership.record(token, post.id)
    end

    with_instance_config(%{"you_markers_max_post_ids" => 2}, fn ->
      conn =
        conn
        |> put_req_cookie("browser_token", token)
        |> put_req_cookie("show_yous", "true")
        |> put_req_header("content-type", "application/json")
        |> post("/api/you-markers/#{board.uri}", %{
          post_ids: Enum.map([thread, first, second], &PublicIds.public_id/1)
        })

      expected = Enum.map([thread, first], &PublicIds.public_id/1) |> Enum.sort()
      assert %{"enabled" => true, "post_ids" => ^expected} = json_response(conn, 200)
    end)
  end
end
