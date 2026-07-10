defmodule EirinchanWeb.SetupControllerTest do
  use EirinchanWeb.ConnCase, async: false

  test "shows the setup page when no admin exists", %{conn: conn} do
    page = conn |> get("/setup") |> html_response(200)

    assert page =~ "Eirinchan Setup"
    assert page =~ "Browser installation is disabled"
    assert page =~ "mix eirinchan.create_admin"
  end

  test "POST /setup is not routed and cannot alter installation files", %{conn: conn} do
    path = Path.join(System.tmp_dir!(), "eirinchan-install-sentinel.json")
    File.write!(path, "sentinel")
    Application.put_env(:eirinchan, :installation_config_path, path)

    on_exit(fn ->
      Application.delete_env(:eirinchan, :installation_config_path)
      File.rm(path)
    end)

    conn = post(conn, "/setup", %{"database_password" => "attacker-controlled"})

    assert response(conn, 404)
    assert File.read!(path) == "sentinel"
  end

  test "setup redirects away once an admin exists", %{conn: conn} do
    moderator_fixture()

    conn = get(conn, "/setup")
    assert redirected_to(conn) == "/manage/login"
  end
end
