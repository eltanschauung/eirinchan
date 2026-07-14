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
    [host | _] = String.split(line, " ")

    assert {:ok, address} = :inet.parse_address(String.to_charlist(host))
    assert tuple_size(address) == 8
    assert line =~ ~r/^2001:db8:[0-9a-f:]+ - - \[\d{2}\/[A-Z][a-z]{2}\/\d{4}:/
    assert line =~ ~s|"GET /api/boards.json HTTP/1.1" 200|
    assert line =~ ~r/"https:\/\/bantculture\.com\/search" "Test Browser"$/
    refute line =~ "top-secret"
    refute line =~ "private"
    refute line =~ "127.0.0.1"
  end

  test "maps client fingerprints to stable documentation-range IPv6 hosts" do
    assert AccessLogPlug.goaccess_host("DcbMNcCZo4uRIMGG") ==
             "2001:db8:dc6:cc35:c099:a38b:9120:c186"

    assert AccessLogPlug.goaccess_host("DcbMNcCZo4uRIMGG") ==
             AccessLogPlug.goaccess_host("DcbMNcCZo4uRIMGG")

    assert AccessLogPlug.goaccess_host("not-base64") == "2001:db8::"
  end

  test "omits successful bant you-marker polling while retaining failures", %{path: path} do
    build_conn()
    |> Map.put(:method, "POST")
    |> Map.put(:request_path, "/api/you-markers/bant")
    |> AccessLogPlug.call([])
    |> send_resp(200, "{}")

    assert File.read!(path) == ""

    build_conn()
    |> Map.put(:method, "POST")
    |> Map.put(:request_path, "/api/you-markers/bant")
    |> AccessLogPlug.call([])
    |> send_resp(500, "error")

    assert File.read!(path) =~ ~s|"POST /api/you-markers/bant HTTP/1.1" 500|
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
