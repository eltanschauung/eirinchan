defmodule EirinchanWeb.ManageSessionControllerTest do
  use EirinchanWeb.ConnCase, async: true
  import Ecto.Query, only: [from: 2]

  setup do
    :ets.delete_all_objects(:eirinchan_manage_login_throttle)
    :ok
  end

  test "login creates a moderator session and logout clears it", %{conn: conn} do
    moderator = moderator_fixture(%{username: "admin", password: "secret123"})

    login_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/manage/login", %{"username" => moderator.username, "password" => "secret123"})

    assert %{
             "data" => %{
               "id" => id,
               "username" => "admin",
               "role" => "admin"
             }
           } = json_response(login_conn, 200)

    session_conn =
      login_conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/manage/session")

    assert %{"data" => %{"id" => ^id, "username" => "admin", "role" => "admin"}} =
             json_response(session_conn, 200)

    logout_conn =
      login_conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> delete("/manage/logout")

    assert %{"status" => "ok"} = json_response(logout_conn, 200)

    unauthorized_conn =
      logout_conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/manage/session")

    assert %{"error" => "unauthorized"} = json_response(unauthorized_conn, 401)
  end

  test "sessions are invalidated after password hash changes", %{conn: conn} do
    moderator = moderator_fixture(%{username: "admin", password: "secret123"})

    login_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/manage/login", %{"username" => moderator.username, "password" => "secret123"})

    updated =
      moderator
      |> Eirinchan.Moderation.ModUser.create_changeset(%{
        "username" => moderator.username,
        "password" => "newsecret456",
        "role" => moderator.role
      })
      |> Ecto.Changeset.apply_changes()

    Eirinchan.Repo.update_all(
      from(user in Eirinchan.Moderation.ModUser, where: user.id == ^moderator.id),
      set: [
        password_hash: updated.password_hash,
        password_salt: updated.password_salt,
        updated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      ]
    )

    assert %{"error" => "unauthorized"} =
             login_conn
             |> recycle()
             |> put_req_header("accept", "application/json")
             |> get("/manage/session")
             |> json_response(401)
  end

  test "sessions are invalidated when the client IP changes", %{conn: conn} do
    moderator = moderator_fixture(%{username: "admin", password: "secret123"})

    login_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/manage/login", %{"username" => moderator.username, "password" => "secret123"})

    assert %{"error" => "unauthorized"} =
             login_conn
             |> recycle()
             |> Map.put(:remote_ip, {8, 8, 8, 8})
             |> put_req_header("accept", "application/json")
             |> get("/manage/session")
             |> json_response(401)
  end

  test "older sessions are invalidated after a new login for the same moderator", %{conn: conn} do
    moderator = moderator_fixture(%{username: "admin", password: "secret123"})

    first_login =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/manage/login", %{"username" => moderator.username, "password" => "secret123"})

    Process.sleep(1100)

    _second_login =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> post("/manage/login", %{"username" => moderator.username, "password" => "secret123"})

    assert %{"error" => "unauthorized"} =
             first_login
             |> recycle()
             |> put_req_header("accept", "application/json")
             |> get("/manage/session")
             |> json_response(401)
  end

  test "sessions expire after configured idle timeout", %{conn: conn} do
    moderator = moderator_fixture(%{username: "admin", password: "secret123"})

    login_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/manage/login", %{"username" => moderator.username, "password" => "secret123"})

    stale_conn =
      login_conn
      |> recycle()
      |> Phoenix.ConnTest.init_test_session(%{
        moderator_user_id: get_session(login_conn, :moderator_user_id),
        secure_manage_token: get_session(login_conn, :secure_manage_token),
        moderator_session_fingerprint: get_session(login_conn, :moderator_session_fingerprint),
        moderator_login_ip: get_session(login_conn, :moderator_login_ip),
        moderator_session_issued_at: get_session(login_conn, :moderator_session_issued_at),
        moderator_session_last_seen_at: System.system_time(:second) - 3 * 60 * 60
      })
      |> put_req_header("accept", "application/json")

    assert %{"error" => "unauthorized"} =
             stale_conn
             |> get("/manage/session")
             |> json_response(401)
  end

  test "sessions expire after configured absolute lifetime", %{conn: conn} do
    moderator = moderator_fixture(%{username: "admin", password: "secret123"})

    login_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/manage/login", %{"username" => moderator.username, "password" => "secret123"})

    stale_conn =
      login_conn
      |> recycle()
      |> Phoenix.ConnTest.init_test_session(%{
        moderator_user_id: get_session(login_conn, :moderator_user_id),
        secure_manage_token: get_session(login_conn, :secure_manage_token),
        moderator_session_fingerprint: get_session(login_conn, :moderator_session_fingerprint),
        moderator_login_ip: get_session(login_conn, :moderator_login_ip),
        moderator_session_issued_at: System.system_time(:second) - 24 * 60 * 60,
        moderator_session_last_seen_at: System.system_time(:second)
      })
      |> put_req_header("accept", "application/json")

    assert %{"error" => "unauthorized"} =
             stale_conn
             |> get("/manage/session")
             |> json_response(401)
  end

  test "manage routes reject anonymous requests", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/manage/boards")

    assert %{"error" => "unauthorized"} = json_response(conn, 401)
  end

  test "login rejects invalid credentials", %{conn: conn} do
    moderator_fixture(%{username: "admin", password: "secret123"})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post("/manage/login", %{"username" => "admin", "password" => "wrong"})

    assert %{"error" => "invalid_credentials"} = json_response(conn, 401)
  end

  test "login is rate limited after repeated failures", %{conn: conn} do
    moderator_fixture(%{username: "admin", password: "secret123"})

    failure =
      fn attempt_conn ->
        attempt_conn
        |> put_req_header("accept", "application/json")
        |> post("/manage/login", %{"username" => "admin", "password" => "wrong"})
      end

    conn = failure.(conn)
    assert %{"error" => "invalid_credentials"} = json_response(conn, 401)

    conn = failure.(recycle(conn))
    assert %{"error" => "invalid_credentials"} = json_response(conn, 401)

    conn = failure.(recycle(conn))
    assert %{"error" => "invalid_credentials"} = json_response(conn, 401)

    conn = failure.(recycle(conn))
    assert %{"error" => "invalid_credentials"} = json_response(conn, 401)

    conn = failure.(recycle(conn))
    assert %{"error" => "rate_limited"} = json_response(conn, 429)
    assert get_resp_header(conn, "retry-after") != []
  end

  test "role hierarchy gates read-only, moderator, and admin manage routes", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    janitor = moderator_fixture(%{role: "janitor"})
    mod = moderator_fixture(%{role: "mod"})
    other_board = board_fixture()

    grant_board_access_fixture(janitor, board)
    grant_board_access_fixture(mod, board)

    janitor_conn =
      conn
      |> login_moderator(janitor)
      |> put_req_header("accept", "application/json")

    assert %{"data" => [%{"uri" => uri}]} =
             janitor_conn
             |> get("/manage/boards")
             |> json_response(200)

    assert uri == board.uri

    assert %{"error" => "forbidden"} =
             janitor_conn
             |> recycle()
             |> login_moderator(janitor)
             |> put_secure_manage_token()
             |> put_req_header("accept", "application/json")
             |> patch("/manage/boards/#{board.uri}/threads/#{thread.id}", %{"locked" => "true"})
             |> json_response(403)

    assert %{"error" => "forbidden"} =
             janitor_conn
             |> recycle()
             |> login_moderator(janitor)
             |> put_req_header("accept", "application/json")
             |> get("/manage/boards/#{other_board.uri}")
             |> json_response(403)

    assert %{"data" => %{"locked" => true}} =
             conn
             |> recycle()
             |> login_moderator(mod)
             |> put_secure_manage_token()
             |> put_req_header("accept", "application/json")
             |> patch("/manage/boards/#{board.uri}/threads/#{thread.id}", %{"locked" => "true"})
             |> json_response(200)

    assert %{"error" => "forbidden"} =
             conn
             |> recycle()
             |> login_moderator(mod)
             |> put_secure_manage_token()
             |> put_req_header("accept", "application/json")
             |> post("/manage/boards", %{uri: "staff", title: "Staff"})
             |> json_response(403)
  end

  test "mutating manage routes reject missing secure tokens", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board)
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(board)

    assert %{"error" => "invalid_secure_token"} =
             conn
             |> login_moderator(moderator)
             |> put_req_header("accept", "application/json")
             |> patch("/manage/boards/#{board.uri}/threads/#{thread.id}", %{"locked" => "true"})
             |> json_response(403)
  end
end
