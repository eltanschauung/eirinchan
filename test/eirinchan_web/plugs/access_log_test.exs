defmodule EirinchanWeb.Plugs.AccessLogTest do
  use EirinchanWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    :ok
  end

  test "logs bounded request metadata without raw identifiers or headers", %{conn: conn} do
    log =
      capture_log(fn ->
        conn
        |> put_req_header("referer", "https://sensitive.example/private")
        |> put_req_header("user-agent", "Secret Browser")
        |> get("/api/boards.json?token=top-secret")
      end)

    assert log =~ "path=\"/api/boards.json\""
    assert log =~ "client_id="
    refute log =~ "top-secret"
    refute log =~ "sensitive.example"
    refute log =~ "Secret Browser"
    refute log =~ "127.0.0.1"
  end
end
