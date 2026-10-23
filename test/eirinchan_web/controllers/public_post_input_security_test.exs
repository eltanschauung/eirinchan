defmodule EirinchanWeb.PublicPostInputSecurityTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.{Boards, Posts}
  alias Eirinchan.Posts.PublicIds

  defp csrf_conn(conn) do
    response = conn |> put_private(:plug_skip_csrf_protection, false) |> get("/csrf-token")
    token = json_response(response, 200)["csrf_token"]

    response
    |> recycle()
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("x-csrf-token", token)
  end

  for route <- [:board, :legacy, :json] do
    @route route
    test "#{route} public posting rejects internal file, identity and state fields", %{conn: conn} do
      board = board_fixture(%{config_overrides: %{poster_ids: true}})
      thread = thread_fixture(board)

      response =
        submit(conn, board, @route, %{
          "thread" => to_string(PublicIds.public_id(thread)),
          "post" => "New Reply",
          "file_path" => "/unrelated/src/placeholder.png",
          "thumb_path" => "/unrelated/thumb/placeholder.png",
          "file_type" => "image/png",
          "file_size" => "123",
          "poster_id" => "FORGED",
          "sticky" => "true",
          "locked" => "true",
          "inactive" => "true",
          "cycle" => "true",
          "ip_subnet" => "192.0.2.99",
          "public_id" => "2147483646",
          "flag_codes" => ["forged"],
          "flag_alts" => ["forged"],
          "cached_reply_count" => "123",
          "legacy_import_id" => "999",
          "__upload_metadata__" => %{"file_path" => "/unrelated/src/placeholder.png"},
          "__upload_entries__" => [],
          "inserted_at" => "2000-01-01T00:00:00Z"
        })

      id = json_response(response, 200)["id"]
      {:ok, saved} = Posts.get_post(board, id)
      assert id == PublicIds.public_id(thread) + 1
      assert Boards.get_board_by_uri(board.uri).next_public_post_id == id + 1
      assert is_nil(saved.file_path) and is_nil(saved.thumb_path)
      assert is_nil(saved.file_type) and is_nil(saved.file_size)
      refute saved.poster_id == "FORGED"
      refute saved.ip_subnet == "192.0.2.99"
      refute saved.sticky or saved.locked or saved.inactive or saved.cycle
      refute "forged" in saved.flag_codes
      assert saved.cached_reply_count == 0
      assert is_nil(saved.legacy_import_id)
      assert saved.inserted_at.year > 2000

      # A subsequent ordinary public post still allocates a normal sequential ID.
      next = submit(build_conn(), board, @route, %{"body" => "Another ordinary post"})
      assert json_response(next, 200)["id"] == id + 1
    end
  end

  defp submit(conn, board, route, attrs) do
    path =
      case route do
        :board -> "/#{board.uri}/post"
        :legacy -> "/post.php"
        :json -> "/api/post"
      end

    conn
    |> csrf_conn()
    |> put_req_header("accept", if(route == :json, do: "application/json", else: "text/html"))
    |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
    |> post(
      path,
      Map.merge(
        %{
          "board" => board.uri,
          "post" => "New Topic",
          "body" => "Ordinary fixture post",
          "json_response" => "1"
        },
        attrs
      )
    )
  end
end
