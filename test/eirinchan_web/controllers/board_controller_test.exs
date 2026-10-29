defmodule EirinchanWeb.BoardControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.BrowserAbuse
  alias Eirinchan.PostOwnership

  defp board_marker(conn) do
    conn.resp_body
    |> Floki.parse_document!()
    |> Floki.find("#board-refresh-target")
    |> Floki.attribute("data-fragment-md5")
    |> hd()
  end

  test "an owned index starts with the same private validator and markup as its first poll", %{
    conn: conn
  } do
    board = board_fixture()
    thread = thread_fixture(board)
    reply = reply_fixture(board, thread)
    token = browser_token("index-bootstrap-owner")
    assert {:ok, _} = PostOwnership.record(token, reply.id)

    initial = conn |> put_req_cookie("browser_token", token) |> get("/#{board.uri}")
    assert html_response(initial, 200) =~ ~s|<span class="own_post">(You)</span>|
    marker = board_marker(initial)
    fragment = initial |> recycle() |> get("/#{board.uri}?fragment=1")
    assert board_marker(fragment) == marker

    initial_tree = initial.resp_body |> Floki.parse_document!() |> Floki.find("#board-threads")
    fragment_tree = fragment.resp_body |> Floki.parse_document!() |> Floki.find("#board-threads")
    assert initial_tree == fragment_tree

    poll =
      initial
      |> recycle()
      |> put_req_header("if-none-match", ~s("#{marker}"))
      |> get("/#{board.uri}?fragment=1")

    assert response(poll, 304) == ""
  end

  test "initial ownership validators remain browser private and honor disabled markers", %{
    conn: conn
  } do
    board = board_fixture()
    thread = thread_fixture(board)
    token = browser_token("private-bootstrap-owner")
    assert {:ok, _} = PostOwnership.record(token, thread.id)
    owner = conn |> put_req_cookie("browser_token", token) |> get("/#{board.uri}")

    visitor =
      conn
      |> put_req_cookie("browser_token", browser_token("other-bootstrap-visitor"))
      |> get("/#{board.uri}")

    refute board_marker(owner) == board_marker(visitor)
    refute visitor.resp_body =~ ~s|<span class="own_post">(You)</span>|

    disabled = owner |> recycle() |> put_req_cookie("show_yous", "false") |> get("/#{board.uri}")
    assert board_marker(disabled) == board_marker(visitor)
    refute disabled.resp_body =~ ~s|<span class="own_post">(You)</span>|

    poll =
      disabled
      |> recycle()
      |> put_req_header("if-none-match", ~s("#{board_marker(disabled)}"))
      |> get("/#{board.uri}?fragment=1")

    assert response(poll, 304) == ""
  end

  test "index expansion metadata uses the complete thread path and versioned preview posts", %{
    conn: conn
  } do
    board = board_fixture(%{config_overrides: %{threads_preview: 1, noko50_min: 2}})
    thread = thread_fixture(board)
    reply_fixture(board, thread)
    reply_fixture(board, thread)
    page = get(conn, "/#{board.uri}") |> html_response(200) |> Floki.parse_document!()
    id = Eirinchan.Posts.PublicIds.public_id(thread)
    [node] = Floki.find(page, "#thread_#{id}")
    assert Floki.attribute(node, "data-thread-url") == ["/#{board.uri}/res/#{id}.html"]
    assert [version] = Floki.attribute(node, "data-preview-version")
    assert byte_size(version) > 20
    assert [_] = Floki.find(node, ".reply[data-fragment-version]")
  end

  test "refreshed messages retain unchanged fragment hashes and change when content changes", %{
    conn: conn
  } do
    board = board_fixture(%{config_overrides: %{"global_message" => "First announcement"}})
    thread = thread_fixture(board, %{body: "Announcement cache test"})

    paths = [
      "/#{board.uri}?fragment=md5",
      "/#{board.uri}/res/#{Eirinchan.Posts.PublicIds.public_id(thread)}.html?fragment=md5"
    ]

    first = Enum.map(paths, fn path -> conn |> get(path) |> response(200) end)

    assert :ok = EirinchanWeb.Announcements.refresh_cache()
    assert Enum.map(paths, fn path -> conn |> get(path) |> response(200) end) == first

    assert {:ok, _} =
             Eirinchan.Boards.update_board(board, %{
               config_overrides: %{"global_message" => "Changed announcement"}
             })

    changed = Enum.map(paths, fn path -> conn |> get(path) |> response(200) end)
    assert Enum.zip(first, changed) |> Enum.all?(fn {before, after_} -> before != after_ end)
  end

  test "a changed theme cannot reuse a full-page fragment validator", %{conn: conn} do
    board = board_fixture()
    _thread = thread_fixture(board, %{body: "Theme validation thread"})
    first = get(conn, "/#{board.uri}")
    [etag] = get_resp_header(first, "etag")

    second =
      first
      |> recycle()
      |> put_req_cookie("theme", "tomorrow")
      |> put_req_header("if-none-match", etag)
      |> get("/#{board.uri}")

    assert html_response(second, 200) =~ "tomorrow.css"
  end

  test "a fresh session cannot reuse a prior full-page validator", %{conn: conn} do
    board = board_fixture()
    _thread = thread_fixture(board, %{body: "Session validation thread"})
    [etag] = conn |> get("/#{board.uri}") |> get_resp_header("etag")

    fresh =
      build_conn()
      |> put_req_header("if-none-match", etag)
      |> get("/#{board.uri}")

    page = html_response(fresh, 200)

    [token] =
      page
      |> Floki.parse_document!()
      |> Floki.find("meta[name='csrf-token']")
      |> Floki.attribute("content")

    session_state = Plug.Conn.get_session(fresh, "_csrf_token")
    assert Plug.CSRFProtection.valid_state_and_csrf_token?(session_state, token)
  end

  test "board index revalidates the complete session-bound document", %{conn: conn} do
    board = board_fixture()
    _thread = thread_fixture(board, %{body: "Thread body", subject: "Thread subject"})

    first_conn = get(conn, "/#{board.uri}")
    assert first_conn.status == 200

    etag =
      first_conn
      |> get_resp_header("etag")
      |> List.first()

    assert is_binary(etag)
    assert get_resp_header(first_conn, "cache-control") == ["private, no-cache"]

    second_conn =
      first_conn
      |> recycle()
      |> put_req_header("if-none-match", etag)
      |> get("/#{board.uri}")

    assert second_conn.status == 200
    assert second_conn.resp_body =~ "csrf-token"
    refute get_resp_header(second_conn, "etag") == [etag]
  end

  test "board index keeps the shared postcontrols form and paginator outside the thread tree", %{
    conn: conn
  } do
    board = board_fixture()
    _thread = thread_fixture(board, %{body: "Thread body", subject: "Thread subject"})

    page = get(conn, "/#{board.uri}") |> html_response(200)

    assert page =~ ~s(<div id="board-threads">)
    assert page =~ ~s(<form name="postcontrols" action="/post.php" method="post">)
    assert page =~ ~s(<div id="board-pages-target" class="board-bottom-nav">)
    assert page =~ ~s(name="delete_post_id")
    assert page =~ ~s(name="report_post_id")

    {threads_pos, _} = :binary.match(page, ~s(<div id="board-threads">))

    {form_pos, _} =
      :binary.match(page, ~s(<form name="postcontrols" action="/post.php" method="post">))

    {pages_pos, _} =
      :binary.match(page, ~s(<div id="board-pages-target" class="board-bottom-nav">))

    assert threads_pos < form_pos
    assert form_pos < pages_pos
    assert length(Regex.scan(~r/id="bottom"/, page)) == 1
  end

  test "board updater fragments preserve server-known (You) markers", %{conn: conn} do
    board = board_fixture(%{uri: "fragmentyous", title: "Fragment Yous"})
    thread = thread_fixture(board, %{body: "Opening body"})
    reply = reply_fixture(board, thread, %{body: "Reply body"})
    token = browser_token("board-fragment-yous")

    assert {:ok, _} = PostOwnership.record(token, reply.id)

    request =
      conn
      |> put_req_cookie("browser_token", token)
      |> put_req_cookie("show_yous", "true")

    public_md5 = request |> get("/#{board.uri}?fragment=md5") |> response(200)
    fragment = request |> recycle() |> get("/#{board.uri}?fragment=1") |> html_response(200)

    assert fragment =~ ~s(data-fragment-md5="#{public_md5}")
    assert fragment =~ ~r/class="post reply you"[^>]*id="reply_\d+"/
    assert fragment =~ ~s|<span class="own_post">(You)</span>|
  end

  test "board fragment revalidation changes when ownership changes", %{conn: conn} do
    board = board_fixture()
    thread = thread_fixture(board, %{body: "Opening body"})
    reply = reply_fixture(board, thread, %{body: "Reply body"})
    token = browser_token("board-revalidation-yous")
    path = "/#{board.uri}?fragment=1"

    request =
      conn |> put_req_cookie("browser_token", token) |> put_req_cookie("show_yous", "true")

    first = get(request, path)
    [old_etag] = get_resp_header(first, "etag")
    assert html_response(first, 200)
    assert {:ok, _} = PostOwnership.record(token, reply.id)
    changed = request |> recycle() |> put_req_header("if-none-match", old_etag) |> get(path)
    assert html_response(changed, 200) =~ ~s|<span class="own_post">(You)</span>|
    [new_etag] = get_resp_header(changed, "etag")
    refute new_etag == old_etag
    unchanged = request |> recycle() |> put_req_header("if-none-match", new_etag) |> get(path)
    assert response(unchanged, 304) == ""

    disabled =
      request
      |> recycle()
      |> put_req_cookie("show_yous", "false")
      |> put_req_header("if-none-match", new_etag)
      |> get(path)

    refute html_response(disabled, 200) =~ ~s|<span class="own_post">(You)</span>|
  end

  test "board index derives watcher paths client-side instead of embedding per-thread watch urls",
       %{
         conn: conn
       } do
    board = board_fixture()
    _thread = thread_fixture(board, %{body: "Thread body", subject: "Thread subject"})

    page = get(conn, "/#{board.uri}") |> html_response(200)

    refute page =~ "data-watch-url="
    refute page =~ "data-unwatch-url="
  end

  test "board index derives post menu targets client-side instead of embedding per-post targets",
       %{
         conn: conn
       } do
    board = board_fixture()
    _thread = thread_fixture(board, %{body: "Thread body", subject: "Thread subject"})

    page = get(conn, "/#{board.uri}") |> html_response(200)

    refute page =~ "data-post-target="
  end

  test "board forms reveal an available captcha for a signaled browser", %{conn: conn} do
    board =
      board_fixture(%{
        config_overrides: %{
          captcha: %{
            enabled: true,
            provider: "native",
            expected_response: "ok",
            challenge: "Risk check",
            mode: "none"
          }
        }
      })

    _thread = thread_fixture(board, %{body: "Thread body"})
    first_conn = get(conn, "/#{board.uri}")
    refute first_conn.resp_body =~ ~s(name="captcha")

    assert {:ok, _signal} =
             BrowserAbuse.record(%{browser_ref: first_conn.assigns.browser_ref}, :rate_limit,
               repo: Eirinchan.Repo
             )

    challenged_page = first_conn |> recycle() |> get("/#{board.uri}") |> html_response(200)
    assert challenged_page =~ "Risk check"
    assert challenged_page =~ ~s(name="captcha")
  end
end
