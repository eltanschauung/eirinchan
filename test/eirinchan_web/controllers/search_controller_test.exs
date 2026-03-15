defmodule EirinchanWeb.SearchControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.Posts.PublicIds

  test "public search returns matching posts only for the selected board", %{conn: conn} do
    board = board_fixture(%{uri: "tea#{System.unique_integer([:positive, :monotonic])}", title: "Tea"})

    other_board =
      board_fixture(%{uri: "meta#{System.unique_integer([:positive, :monotonic])}", title: "Meta"})

    {:ok, thread, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{"body" => "green tea leaf", "subject" => "tea", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    {:ok, _other_thread, _meta} =
      Eirinchan.Posts.create_post(
        other_board,
        %{"body" => "meta tea", "subject" => "meta", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, other_board.config_overrides),
        request: %{referer: "http://example.test/#{other_board.uri}/index.html"}
      )

    page =
      conn
      |> get("/search.php", %{"search" => "leaf", "board" => board.uri})
      |> html_response(200)

    assert page =~ "Search"
    assert page =~ "green tea leaf"
    assert page =~ "/#{board.uri}/res/#{PublicIds.public_id(thread)}.html"
    assert page =~ "1 result in"
    assert page =~ "/#{board.uri}/ - #{board.title}"
    refute page =~ "meta tea"
  end

  test "public search logs queries", %{conn: _conn} do
    board =
      board_fixture(%{
        uri: "tea#{System.unique_integer([:positive, :monotonic])}",
        config_overrides: %{
          search_queries_per_minutes: [1, 1],
          search_queries_per_minutes_all: [0, 1]
        }
      })

    conn = %{build_conn() | remote_ip: {198, 51, 100, 99}}

    first_page =
      conn
      |> get("/search.php", %{"search" => "tripcode", "board" => board.uri})
      |> html_response(200)

    assert first_page =~ "(No results.)"

    assert Enum.any?(
             Eirinchan.Antispam.list_search_queries("198.51.100.99", repo: Eirinchan.Repo),
             &(&1.query == "tripcode" and &1.board_id == board.id)
           )
  end

  test "public search applies global query throttles across IPs", %{conn: _conn} do
    board =
      board_fixture(%{
        uri: "rate#{System.unique_integer([:positive, :monotonic])}",
        config_overrides: %{
          search_queries_per_minutes: [0, 1],
          search_queries_per_minutes_all: [1, 1]
        }
      })

    first_conn = %{build_conn() | remote_ip: {198, 51, 100, 10}}
    second_conn = %{build_conn() | remote_ip: {198, 51, 100, 11}}

    assert first_conn
           |> get("/search.php", %{"search" => "tripcode", "board" => board.uri})
           |> html_response(200) =~ "(No results.)"

    assert second_conn
           |> get("/search.php", %{"search" => "tripcode", "board" => board.uri})
           |> html_response(200) =~ "Wait a while before searching again, please."
  end

  test "public search supports id, thread, subject, and name filters", %{conn: conn} do
    board = board_fixture(%{uri: "search#{System.unique_integer([:positive, :monotonic])}", title: "Search"})

    {:ok, thread, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{
          "name" => "Alice",
          "subject" => "Tea topic",
          "body" => "green leaf",
          "post" => "New Topic"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    {:ok, reply, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{
          "thread" => Integer.to_string(PublicIds.public_id(thread)),
          "name" => "Bob",
          "subject" => "Reply subject",
          "body" => "reply body",
          "post" => "New Reply"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    assert get(conn, "/search.php", %{"search" => "id:#{PublicIds.public_id(reply)}", "board" => board.uri})
           |> html_response(200) =~ "reply body"

    assert get(conn, "/search.php", %{"search" => "thread:#{PublicIds.public_id(thread)}", "board" => board.uri})
           |> html_response(200) =~ "reply body"

    assert get(conn, "/search.php", %{"search" => "subject:\"Tea topic\"", "board" => board.uri})
           |> html_response(200) =~ "green leaf"

    assert get(conn, "/search.php", %{"search" => "name:Alice", "board" => board.uri})
           |> html_response(200) =~ "green leaf"
  end

  test "public search renders thread-aware result objects for replies", %{conn: conn} do
    board = board_fixture(%{uri: "render#{System.unique_integer([:positive, :monotonic])}", title: "Render"})

    {:ok, thread, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{
          "name" => "Op",
          "subject" => "Thread subject",
          "body" => "thread body",
          "post" => "New Topic"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    {:ok, _reply, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{
          "thread" => Integer.to_string(PublicIds.public_id(thread)),
          "name" => "Reply",
          "body" => "reply body match",
          "post" => "New Reply"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    page =
      conn
      |> get("/search.php", %{"search" => "reply body", "board" => board.uri})
      |> html_response(200)

    assert page =~ "reply body match"
    assert page =~ "/#{board.uri}/res/#{PublicIds.public_id(thread)}.html"
    assert page =~ "1 result in"
  end

  test "public search supports wildcard and phrase search semantics", %{conn: conn} do
    board = board_fixture(%{uri: "phrase#{System.unique_integer([:positive, :monotonic])}", title: "Phrase"})

    {:ok, _thread, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{
          "name" => "Alice",
          "subject" => "Green Tea Topic",
          "body" => "green tea leaf piles only",
          "post" => "New Topic"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    {:ok, _thread, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{
          "name" => "Bob",
          "subject" => "Black Tea Topic",
          "body" => "black tea dust only",
          "post" => "New Topic"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    phrase_page =
      conn
      |> get("/search.php", %{"search" => "\"green tea\" leaf*", "board" => board.uri})
      |> html_response(200)

    assert phrase_page =~ "green tea leaf piles only"
    refute phrase_page =~ "black tea dust only"

    subject_page =
      conn
      |> get("/search.php", %{"search" => "subject:\"Green Tea Topic\"", "board" => board.uri})
      |> html_response(200)

    assert subject_page =~ "Green Tea Topic"
    refute subject_page =~ "Black Tea Topic"
  end

  test "public search can be disabled globally", %{conn: conn} do
    previous = Application.get_env(:eirinchan, :search_overrides, %{})
    Application.put_env(:eirinchan, :search_overrides, %{search_enabled: false})
    on_exit(fn -> Application.put_env(:eirinchan, :search_overrides, previous) end)

    page = conn |> get("/search.php", %{"search" => "leaf"}) |> html_response(200)

    assert page =~ "Post search is disabled"
    refute page =~ "Wait a while before searching again, please."
  end

  test "public search respects board allowlists and denylists", %{conn: conn} do
    allowed_board =
      board_fixture(%{uri: "allow#{System.unique_integer([:positive, :monotonic])}", title: "Allow"})

    blocked_board =
      board_fixture(%{uri: "block#{System.unique_integer([:positive, :monotonic])}", title: "Block"})

    {:ok, _thread, _meta} =
      Eirinchan.Posts.create_post(
        allowed_board,
        %{"body" => "allowed search result", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, allowed_board.config_overrides),
        request: %{referer: "http://example.test/#{allowed_board.uri}/index.html"}
      )

    {:ok, _thread, _meta} =
      Eirinchan.Posts.create_post(
        blocked_board,
        %{"body" => "blocked search result", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, blocked_board.config_overrides),
        request: %{referer: "http://example.test/#{blocked_board.uri}/index.html"}
      )

    previous = Application.get_env(:eirinchan, :search_overrides, %{})

    Application.put_env(:eirinchan, :search_overrides, %{
      search_allowed_boards: [allowed_board.uri],
      search_disallowed_boards: [blocked_board.uri]
    })

    on_exit(fn -> Application.put_env(:eirinchan, :search_overrides, previous) end)

    page = conn |> get("/search.php") |> html_response(200)

    assert page =~ ~s(value="#{allowed_board.uri}")
    refute page =~ ~s(value="#{blocked_board.uri}")

    blocked_page =
      conn
      |> get("/search.php", %{"search" => "search result", "board" => blocked_board.uri})
      |> html_response(200)

    refute blocked_page =~ "allowed search result"
    refute blocked_page =~ "blocked search result"
  end
end
