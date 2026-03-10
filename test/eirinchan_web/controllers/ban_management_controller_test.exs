defmodule EirinchanWeb.BanManagementControllerTest do
  use EirinchanWeb.ConnCase, async: true

  alias Eirinchan.Bans

  test "moderators can create, list, and update board bans", %{conn: conn} do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(board)

    create_conn =
      conn
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> post("/manage/boards/#{board.uri}/bans", %{
        "ip_subnet" => "198.51.100.7",
        "reason" => "Spam"
      })

    assert %{"data" => %{"id" => ban_id, "ip_subnet" => ip_subnet, "reason" => "Spam"}} =
             json_response(create_conn, 201)

    assert is_binary(ip_subnet)

    list_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_req_header("accept", "application/json")
      |> get("/manage/boards/#{board.uri}/bans")

    assert %{"data" => [%{"id" => ^ban_id, "active" => true}]} = json_response(list_conn, 200)

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{board.uri}/bans/#{ban_id}", %{
        "reason" => "Resolved spammer",
        "active" => "false"
      })

    assert %{"data" => %{"id" => ^ban_id, "reason" => "Resolved spammer", "active" => false}} =
             json_response(update_conn, 200)
  end

  test "moderators can list and resolve board ban appeals", %{conn: conn} do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(board)

    {:ok, ban} =
      Bans.create_ban(%{
        board_id: board.id,
        mod_user_id: moderator.id,
        ip_subnet: "198.51.100.9",
        reason: "Spam"
      })

    {:ok, appeal} = Bans.create_appeal(ban.id, %{body: "Please review"})

    list_conn =
      conn
      |> login_moderator(moderator)
      |> put_req_header("accept", "application/json")
      |> get("/manage/boards/#{board.uri}/ban-appeals")

    assert %{"data" => [%{"id" => appeal_id, "status" => "open", "body" => "Please review"}]} =
             json_response(list_conn, 200)

    assert appeal_id == appeal.id

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{board.uri}/ban-appeals/#{appeal.id}", %{
        "status" => "resolved",
        "resolution_note" => "Reviewed"
      })

    assert %{
             "data" => %{
               "id" => ^appeal_id,
               "status" => "resolved",
               "resolution_note" => "Reviewed"
             }
           } = json_response(update_conn, 200)
  end

  test "board ban routes reject moderators without access", %{conn: conn} do
    board = board_fixture()
    other_board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(other_board)

    conn =
      conn
      |> login_moderator(moderator)
      |> put_req_header("accept", "application/json")
      |> get("/manage/boards/#{board.uri}/bans")

    assert %{"error" => "forbidden"} = json_response(conn, 403)
  end
end
