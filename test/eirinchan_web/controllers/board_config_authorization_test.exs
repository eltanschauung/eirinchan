defmodule EirinchanWeb.BoardConfigAuthorizationTest do
  use EirinchanWeb.ConnCase, async: false

  for role <- ["janitor", "mod", "admin"] do
    @role role
    test "#{role} board index and show apply the configuration permission", %{conn: conn} do
      board =
        board_fixture(%{
          config_overrides: %{
            secure_trip_salt: "test-only-salt",
            ip_access_passwords: ["test-only-passphrase"]
          }
        })

      moderator = moderator_fixture(%{role: @role}) |> grant_board_access_fixture(board)

      for path <- ["/manage/boards", "/manage/boards/#{board.uri}"] do
        response =
          conn
          |> recycle()
          |> login_moderator(moderator)
          |> put_req_header("accept", "application/json")
          |> get(path)
          |> json_response(200)

        data = if is_list(response["data"]), do: hd(response["data"]), else: response["data"]
        assert data["uri"] == board.uri

        if @role == "admin" do
          assert data["config_overrides"]["secure_trip_salt"] == "test-only-salt"
        else
          refute Map.has_key?(data, "config_overrides")
          refute inspect(response) =~ "test-only-"
        end
      end
    end
  end

  test "unassigned janitors cannot enumerate or fetch other boards", %{conn: conn} do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "janitor"})
    conn = conn |> login_moderator(moderator) |> put_req_header("accept", "application/json")
    assert json_response(get(conn, "/manage/boards"), 200)["data"] == []

    assert json_response(get(conn, "/manage/boards/#{board.uri}"), 403)["error"] ==
             "forbidden"
  end

  test "anonymous requests remain denied", %{conn: conn} do
    assert json_response(get(conn, "/manage/boards"), 401)["error"] == "unauthorized"
  end

  test "serializer defaults to excluding configuration without an explicit moderator" do
    board = board_fixture(%{config_overrides: %{secure_trip_salt: "test-only-salt"}})

    refute Map.has_key?(
             EirinchanWeb.BoardManagementJSON.show(%{board: board}).data,
             :config_overrides
           )
  end
end
