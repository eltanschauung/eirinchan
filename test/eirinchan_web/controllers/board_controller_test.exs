defmodule EirinchanWeb.BoardControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.BrowserAbuse
  alias Eirinchan.PostOwnership

  test "board index returns an etag and honors if-none-match", %{conn: conn} do
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
      conn
      |> recycle()
      |> put_req_header("if-none-match", etag)
      |> get("/#{board.uri}")

    assert second_conn.status == 304
    assert second_conn.resp_body == ""
    assert get_resp_header(second_conn, "etag") == [etag]
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
             BrowserAbuse.record(%{browser_ref: first_conn.assigns.browser_token}, :rate_limit,
               repo: Eirinchan.Repo
             )

    challenged_page = first_conn |> recycle() |> get("/#{board.uri}") |> html_response(200)
    assert challenged_page =~ "Risk check"
    assert challenged_page =~ ~s(name="captcha")
  end
end
