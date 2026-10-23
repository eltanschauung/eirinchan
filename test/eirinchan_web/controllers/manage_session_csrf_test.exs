defmodule EirinchanWeb.ManageSessionCsrfTest do
  use EirinchanWeb.ConnCase, async: false

  setup do
    :ets.delete_all_objects(:eirinchan_manage_login_throttle)
    :ok
  end

  test "cross-origin form login without CSRF cannot establish a session", %{conn: conn} do
    moderator = moderator_fixture(%{password: "test-only password"})

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("origin", "https://untrusted.invalid")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(
        "/manage/login",
        URI.encode_query(%{"username" => moderator.username, "password" => "test-only password"})
      )
    end
  end

  test "JSON login rejects missing and incorrect tokens", %{conn: conn} do
    moderator = moderator_fixture(%{password: "test-only password"})

    for token <- [nil, "incorrect-token"] do
      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        request = conn |> put_private(:plug_skip_csrf_protection, false)
        request = if token, do: put_req_header(request, "x-csrf-token", token), else: request

        request
        |> put_req_header("content-type", "application/json")
        |> post(
          "/manage/login",
          Jason.encode!(%{username: moderator.username, password: "test-only password"})
        )
      end
    end
  end

  test "matching token and session allow JSON login and logout", %{conn: conn} do
    moderator = moderator_fixture(%{password: "test-only password"})

    logged_in =
      conn
      |> with_csrf()
      |> post("/manage/login", %{
        "username" => moderator.username,
        "password" => "test-only password"
      })

    assert json_response(logged_in, 200)["data"]["id"] == moderator.id
    assert get_session(logged_in, :moderator_user_id) == moderator.id

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      logged_in
      |> recycle()
      |> delete_req_header("x-csrf-token")
      |> put_private(:plug_skip_csrf_protection, false)
      |> delete("/manage/logout")
    end

    logged_out = logged_in |> recycle() |> with_csrf() |> delete("/manage/logout")
    assert json_response(logged_out, 200) == %{"status" => "ok"}
    refute get_session(logged_out, :moderator_user_id)
  end

  test "token from a different browser session is rejected", %{conn: conn} do
    first = conn |> with_csrf()
    [token] = get_req_header(first, "x-csrf-token")

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      build_conn()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("x-csrf-token", token)
      |> post("/manage/login", %{})
    end
  end

  defp with_csrf(conn) do
    response =
      conn
      |> put_req_header("accept", "text/html")
      |> put_private(:plug_skip_csrf_protection, false)
      |> get("/csrf-token")

    token = json_response(response, 200)["csrf_token"]

    response
    |> recycle()
    |> put_req_header("accept", "application/json")
    |> put_private(:plug_skip_csrf_protection, false)
    |> put_req_header("x-csrf-token", token)
  end
end
