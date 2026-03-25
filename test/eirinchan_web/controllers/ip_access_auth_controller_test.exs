defmodule EirinchanWeb.IpAccessAuthControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.IpAccessEntry
  alias Eirinchan.Settings

  setup do
    original_path = Application.get_env(:eirinchan, :instance_config_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "eirinchan-ipauth-controller-#{System.unique_integer([:positive])}.json"
      )

    File.rm(path)
    Application.put_env(:eirinchan, :instance_config_path, path)
    Eirinchan.Repo.delete_all(IpAccessEntry)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
    end)

    %{settings_path: path}
  end

  test "default auth page renders without the site layout", %{conn: conn} do
    html = get(conn, "/auth") |> html_response(200)

    assert html =~ "IP Access Auth"
    assert html =~ "Enter a password to gain access."
    refute html =~ "Theme"
    refute html =~ "Signed in as"
  end

  test "custom auth path rewrites to the auth controller and posts update the configured access entries",
       %{
         conn: conn
       } do
    {:ok, _config} =
      Settings.update_instance_config_from_json(
        Jason.encode!(%{
          ip_access_passwords: ["letmein", "other"],
          ip_access_auth: %{
            auth_path: "/door",
            message: "Knock first.",
            title: "Secret Door"
          }
        })
      )

    page = get(conn, "/door") |> html_response(200)
    assert page =~ "Knock first."
    assert page =~ "<title>Secret Door</title>"

    post_conn =
      conn
      |> recycle()
      |> post("/door", %{"password" => "LETMEIN"})

    body = html_response(post_conn, 200)
    assert body =~ "Access granted."

    assert [%IpAccessEntry{ip: "127.0.0.0/24", password: "letmein", granted_at: %NaiveDateTime{}}] =
             Eirinchan.Repo.all(IpAccessEntry)
  end

  test "invalid passwords return validation feedback", %{conn: conn} do
    conn = post(conn, "/auth", %{"password" => "wrong"})
    assert html_response(conn, 422) =~ "Invalid password."
  end
end
