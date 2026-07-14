defmodule EirinchanWeb.IpAccessAuthControllerTest do
  use EirinchanWeb.ConnCase, async: false
  import ExUnit.CaptureLog

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
    :ets.delete_all_objects(:eirinchan_ip_access_auth_throttle)

    on_exit(fn ->
      Application.put_env(:eirinchan, :instance_config_path, original_path)
      File.rm(path)
      :ets.delete_all_objects(:eirinchan_ip_access_auth_throttle)
    end)

    %{settings_path: path}
  end

  test "default auth page renders without the site layout", %{conn: conn} do
    html = get(conn, "/auth") |> html_response(200)

    assert html =~ "IP Access Auth"
    assert html =~ "Enter a password to gain access."
    refute html =~ "Theme"
    refute html =~ "Signed in as"
    assert html =~ ~s(href="mailto:example@example.com")
  end

  test "auth contact email comes from instance config", %{conn: conn} do
    {:ok, _config} =
      Settings.update_instance_config_from_json(
        Jason.encode!(%{contact_email: "contact@instance.test"})
      )

    html = get(conn, "/auth") |> html_response(200)

    assert html =~ ~s(href="mailto:contact@instance.test")
    refute html =~ ~s(href="mailto:example@example.com")
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
    assert body =~ ~s(data-redirect-url="/")
    assert body =~ ~s(src="/js/auth-redirect.js")
    refute body =~ "setTimeout(function"

    assert [%IpAccessEntry{ip: "127.0.0.0/24", password: stored, granted_at: %NaiveDateTime{}}] =
             Eirinchan.Repo.all(IpAccessEntry)

    assert Eirinchan.CredentialHash.verify("letmein", stored, :ip_access)
    refute stored == "letmein"
  end

  test "invalid passwords return validation feedback", %{conn: conn} do
    {conn, log} = with_log(fn -> post(conn, "/auth", %{"password" => "wrong"}) end)
    assert html_response(conn, 422) =~ "Invalid password."
    assert log =~ ~s|"event":"auth.ip_access.rejected"|
    assert log =~ ~s|"outcome":"invalid_password"|
    refute log =~ "wrong"
  end

  test "invalid authentication attempts are throttled per subnet", %{conn: conn} do
    {:ok, _config} =
      Settings.update_instance_config_from_json(
        Jason.encode!(%{
          ip_access_passwords: ["door"],
          ip_access_auth: %{max_attempts: 2, global_max_attempts: 100, lockout_seconds: 60}
        })
      )

    first = post(conn, "/auth", %{"password" => "wrong"})
    assert html_response(first, 422) =~ "Invalid password."

    limited = conn |> recycle() |> post("/auth", %{"password" => "still-wrong"})
    assert html_response(limited, 429) =~ "Too many attempts."
    assert get_resp_header(limited, "retry-after") == ["60"]
  end

  test "successful authentication normalizes same-origin referrers to local paths", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/bant/res/123?mode=compact#456")
      |> post("/auth", %{"password" => configured_password("door")})

    body = html_response(conn, 200)
    assert body =~ ~s(data-redirect-url="/bant/res/123?mode=compact#456")
    assert body =~ ~s(href="/bant/res/123?mode=compact#456")
  end

  test "successful authentication rejects unsafe referrers", %{conn: conn} do
    for referer <- [
          "https://attacker.example/phish",
          "//attacker.example/phish",
          "/\\attacker.example/phish",
          "http://user@www.example.com/phish"
        ] do
      response =
        conn
        |> recycle()
        |> put_req_header("referer", referer)
        |> post("/auth", %{"password" => configured_password("door")})
        |> html_response(200)

      assert response =~ ~s(data-redirect-url="/")
      refute response =~ "attacker.example"
    end
  end

  defp configured_password(password) do
    {:ok, _config} =
      Settings.update_instance_config_from_json(Jason.encode!(%{ip_access_passwords: [password]}))

    password
  end
end
