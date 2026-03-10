defmodule EirinchanWeb.IpManagementControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.Repo

  test "board and global ip views expose posts and notes", %{conn: conn} do
    with_instance_config(%{}, fn ->
      board = board_fixture()
      other_board = board_fixture()
      moderator = moderator_fixture(%{role: "mod"})

      grant_board_access_fixture(moderator, board)
      grant_board_access_fixture(moderator, other_board)

      thread = thread_fixture(board, %{body: "Board history body"})
      other_thread = thread_fixture(other_board, %{body: "Other history body"})

      {:ok, _thread} = Repo.update(Ecto.Changeset.change(thread, ip_subnet: "198.51.100.4"))

      {:ok, _other_thread} =
        Repo.update(Ecto.Changeset.change(other_thread, ip_subnet: "198.51.100.4"))

      note_conn =
        conn
        |> login_moderator(moderator)
        |> put_secure_manage_token()
        |> put_req_header("accept", "application/json")
        |> post("/manage/boards/#{board.uri}/ip/198.51.100.4/notes", %{"body" => "Watch this IP"})

      assert %{"data" => %{"ip_subnet" => "198.51.100.4", "body" => "Watch this IP"}} =
               json_response(note_conn, 201)

      board_view =
        conn
        |> recycle()
        |> login_moderator(moderator)
        |> put_req_header("accept", "application/json")
        |> get("/manage/boards/#{board.uri}/ip/198.51.100.4")

      assert %{"data" => %{"ip" => "198.51.100.4", "posts" => posts, "notes" => notes}} =
               json_response(board_view, 200)

      assert Enum.map(posts, & &1["id"]) == [thread.id]
      assert Enum.map(notes, & &1["body"]) == ["Watch this IP"]

      global_view =
        conn
        |> recycle()
        |> login_moderator(moderator)
        |> put_req_header("accept", "application/json")
        |> get("/manage/ip/198.51.100.4")

      assert %{"data" => %{"posts" => global_posts}} = json_response(global_view, 200)
      assert Enum.map(global_posts, & &1["id"]) == [other_thread.id, thread.id]
    end)
  end

  test "board ip views reject moderators without board access", %{conn: conn} do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"})

    conn =
      conn
      |> login_moderator(moderator)
      |> put_req_header("accept", "application/json")
      |> get("/manage/boards/#{board.uri}/ip/198.51.100.4")

    assert %{"error" => "forbidden"} = json_response(conn, 403)
  end

  test "ip notes can be updated and deleted through board moderation routes", %{conn: conn} do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"})
    grant_board_access_fixture(moderator, board)

    note_conn =
      conn
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> post("/manage/boards/#{board.uri}/ip/198.51.100.4/notes", %{"body" => "Watch this IP"})

    note_id = json_response(note_conn, 201)["data"]["id"]

    update_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> patch("/manage/boards/#{board.uri}/ip/198.51.100.4/notes/#{note_id}", %{
        "body" => "Updated note"
      })

    assert %{"data" => %{"body" => "Updated note"}} = json_response(update_conn, 200)

    delete_conn =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> delete("/manage/boards/#{board.uri}/ip/198.51.100.4/notes/#{note_id}")

    assert response(delete_conn, 204)
  end

  test "delete-by-ip removes posts for a board or across accessible boards", %{conn: conn} do
    board = board_fixture()
    other_board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"})

    grant_board_access_fixture(moderator, board)
    grant_board_access_fixture(moderator, other_board)

    thread = thread_fixture(board, %{body: "Board history body"})
    reply = reply_fixture(board, thread, %{body: "Board reply body"})
    other_thread = thread_fixture(other_board, %{body: "Other history body"})

    {:ok, _thread} = Repo.update(Ecto.Changeset.change(thread, ip_subnet: "198.51.100.9"))
    {:ok, _reply} = Repo.update(Ecto.Changeset.change(reply, ip_subnet: "198.51.100.9"))

    {:ok, _other_thread} =
      Repo.update(Ecto.Changeset.change(other_thread, ip_subnet: "198.51.100.9"))

    board_delete =
      conn
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> delete("/manage/boards/#{board.uri}/ip/198.51.100.9/posts")

    assert %{"data" => %{"count" => 2, "board_ids" => [deleted_board_id]}} =
             json_response(board_delete, 200)

    assert deleted_board_id == board.id
    assert Repo.get(Eirinchan.Posts.Post, thread.id) == nil
    assert Repo.get(Eirinchan.Posts.Post, reply.id) == nil
    assert Repo.get(Eirinchan.Posts.Post, other_thread.id).id == other_thread.id

    global_delete =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> delete("/manage/ip/198.51.100.9/posts")

    assert %{"data" => %{"count" => 1, "board_ids" => [other_deleted_board_id]}} =
             json_response(global_delete, 200)

    assert other_deleted_board_id == other_board.id
    assert Repo.get(Eirinchan.Posts.Post, other_thread.id) == nil
  end

  test "janitors receive cloaked ip values in json views", %{conn: conn} do
    with_instance_config(%{"ipcrypt_key" => "whalenic"}, fn ->
      board = board_fixture()
      janitor = moderator_fixture(%{role: "janitor"})
      grant_board_access_fixture(janitor, board)

      thread = thread_fixture(board, %{body: "Board history body"})
      {:ok, _thread} = Repo.update(Ecto.Changeset.change(thread, ip_subnet: "198.51.100.4"))

      board_view =
        conn
        |> login_moderator(janitor)
        |> put_req_header("accept", "application/json")
        |> get("/manage/boards/#{board.uri}/ip/198.51.100.4")

      assert %{"data" => %{"ip" => cloaked_ip, "posts" => [%{"ip_subnet" => cloaked_post_ip}]}} =
               json_response(board_view, 200)

      assert cloaked_ip =~ "Cloak:"
      assert cloaked_post_ip == cloaked_ip
      refute cloaked_ip == "198.51.100.4"
    end)
  end

  defp with_instance_config(config, fun) do
    original_path = Application.get_env(:eirinchan, :instance_config_path)
    path = Path.join(System.tmp_dir!(), "eirinchan-ipjson-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(config))

    try do
      Application.put_env(:eirinchan, :instance_config_path, path)
      fun.()
    after
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end
  end
end
