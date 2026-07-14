defmodule EirinchanWeb.Plugs.AccessLogTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.AccessLog
  alias EirinchanWeb.Plugs.AccessLog, as: AccessLogPlug

  setup do
    path =
      Path.join(System.tmp_dir!(), "eirinchan-access-#{System.unique_integer([:positive])}.log")

    start_supervised!({AccessLog, path: path})
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "writes GoAccess-compatible Combined records without raw IPs or query secrets", %{
    conn: conn,
    path: path
  } do
    conn
    |> put_req_header("referer", "https://bantculture.com/search?q=private#result")
    |> put_req_header("user-agent", "Test Browser")
    |> get("/api/boards.json?token=top-secret")

    [line] = File.read!(path) |> String.split("\n", trim: true)

    assert line =~ ~r/^[-_A-Za-z0-9]+ - - \[\d{2}\/[A-Z][a-z]{2}\/\d{4}:/
    assert line =~ ~s|"GET /api/boards.json HTTP/1.1" 200|
    assert line =~ ~r/"https:\/\/bantculture\.com\/search" "Test Browser"$/
    refute line =~ "top-secret"
    refute line =~ "private"
    refute line =~ "127.0.0.1"
  end

  test "bounds and escapes untrusted Combined-log fields", %{conn: conn} do
    now = ~U[2026-07-14 12:34:56Z]

    line =
      conn
      |> put_req_header("user-agent", String.duplicate("x", 600) <> "\nforged")
      |> Map.put(:status, 204)
      |> AccessLogPlug.format_line("client-id", now)

    assert line =~ ~s|client-id - - [14/Jul/2026:12:34:56 +0000]|
    assert String.split(line, "\n", trim: true) |> length() == 1
    refute line =~ "forged"
  end

  test "weekly purge removes only records older than the cutoff", %{path: path} do
    old = ~s|old - - [06/Jul/2026:23:59:59 +0000] "GET /old HTTP/1.1" 200 1 "-" "-"\n|
    fresh = ~s|new - - [07/Jul/2026:00:00:00 +0000] "GET /new HTTP/1.1" 200 1 "-" "-"\n|
    malformed = "retain malformed forensic line\n"

    :ok = AccessLog.write(old <> fresh <> malformed)

    assert {:ok, 1} = AccessLog.purge_older_than(~U[2026-07-07 00:00:00Z])
    assert File.read!(path) == fresh <> malformed
    assert %{purged_lines: 1, writes: 1} = AccessLog.stats()
  end
end
