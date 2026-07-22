defmodule EirinchanWeb.SearchControllerTest do
  use EirinchanWeb.ConnCase, async: false
  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog

  alias Eirinchan.Posts.PublicIds
  alias Eirinchan.Repo

  setup do
    Eirinchan.Statistics.create_counter_table()
    :ets.delete_all_objects(Eirinchan.Statistics.counter_table())
    :ok
  end

  test "public search returns matching posts only for the selected board", %{conn: conn} do
    board =
      board_fixture(%{uri: "tea#{System.unique_integer([:positive, :monotonic])}", title: "Tea"})

    other_board =
      board_fixture(%{
        uri: "meta#{System.unique_integer([:positive, :monotonic])}",
        title: "Meta"
      })

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
    assert page =~ "1 result"
    assert page =~ "/#{board.uri}/ - #{board.title}"
    refute page =~ "meta tea"
  end

  test "public search persists only bounded antispam state", %{conn: _conn} do
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
             Eirinchan.Antispam.list_public_activity_entries("198.51.100.99",
               repo: Eirinchan.Repo
             ),
             &(&1.activity == "search" and &1.board_id == board.id)
           )
  end

  test "public search bounds query length and term complexity", %{conn: conn} do
    board =
      board_fixture(%{
        uri: "bound#{System.unique_integer([:positive, :monotonic])}",
        config_overrides: %{search_max_query_length: 20, search_max_terms: 2}
      })

    long_page =
      conn
      |> get("/search.php", %{"search" => String.duplicate("x", 21), "board" => board.uri})
      |> html_response(200)

    assert long_page =~ "Search queries are limited to 20 characters."

    complex_page =
      build_conn()
      |> get("/search.php", %{"search" => "one two three", "board" => board.uri})
      |> html_response(200)

    assert complex_page =~ "Search queries are limited to 2 terms."
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

    {second_page, log} =
      with_log(fn ->
        second_conn
        |> get("/search.php", %{"search" => "tripcode", "board" => board.uri})
        |> html_response(200)
      end)

    assert second_page =~ "Wait a while before searching again, please."
    assert log =~ ~s|"event":"search.rejected"|
    assert log =~ ~s|"outcome":"rate_limited"|
    assert log =~ ~s|"query_length":8|
    refute log =~ "tripcode"
  end

  test "public search supports id, thread, subject, and name filters", %{conn: conn} do
    board =
      board_fixture(%{
        uri: "search#{System.unique_integer([:positive, :monotonic])}",
        title: "Search"
      })

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

    assert get(conn, "/search.php", %{
             "search" => "id:#{PublicIds.public_id(reply)}",
             "board" => board.uri
           })
           |> html_response(200) =~ "reply body"

    assert get(conn, "/search.php", %{
             "search" => "thread:#{PublicIds.public_id(thread)}",
             "board" => board.uri
           })
           |> html_response(200) =~ "reply body"

    assert get(conn, "/search.php", %{"search" => "subject:\"Tea topic\"", "board" => board.uri})
           |> html_response(200) =~ "green leaf"

    assert get(conn, "/search.php", %{"search" => "name:Alice", "board" => board.uri})
           |> html_response(200) =~ "green leaf"
  end

  test "public search renders thread-aware result objects for replies", %{conn: conn} do
    board =
      board_fixture(%{
        uri: "render#{System.unique_integer([:positive, :monotonic])}",
        title: "Render"
      })

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
    assert page =~ "1 result"
  end

  test "public search renders visible timestamps using the browser timezone cookie", %{conn: conn} do
    board =
      board_fixture(%{
        uri: "searchzone#{System.unique_integer([:positive, :monotonic])}",
        title: "Search Zone"
      })

    {:ok, thread, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{
          "name" => "Op",
          "subject" => "Thread subject",
          "body" => "search timezone body",
          "post" => "New Topic"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    inserted_at = ~U[2026-03-13 12:00:00Z]

    Repo.update_all(from(post in Eirinchan.Posts.Post, where: post.id == ^thread.id),
      set: [inserted_at: inserted_at]
    )

    page =
      conn
      |> put_req_cookie("timezone_offset", "-180")
      |> get("/search.php", %{"search" => "timezone", "board" => board.uri})
      |> html_response(200)

    assert page =~ "03/13/26 (Fri) 09:00:00"
    refute page =~ "03/13/26 (Fri) 12:00:00"
  end

  test "public search supports wildcard and phrase search semantics", %{conn: conn} do
    board =
      board_fixture(%{
        uri: "phrase#{System.unique_integer([:positive, :monotonic])}",
        title: "Phrase"
      })

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
      board_fixture(%{
        uri: "allow#{System.unique_integer([:positive, :monotonic])}",
        title: "Allow"
      })

    blocked_board =
      board_fixture(%{
        uri: "block#{System.unique_integer([:positive, :monotonic])}",
        title: "Block"
      })

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

  test "advanced search renders a server-built console and searches all allowed boards", %{
    conn: conn
  } do
    first = board_fixture(%{uri: "globala#{System.unique_integer([:positive, :monotonic])}"})
    second = board_fixture(%{uri: "globalb#{System.unique_integer([:positive, :monotonic])}"})

    for {board, marker} <- [{first, "first marker"}, {second, "second marker"}] do
      {:ok, _post, _meta} =
        Eirinchan.Posts.create_post(
          board,
          %{"body" => "shared phrase #{marker}", "post" => "New Topic"},
          config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
          request: %{referer: "http://example.test/#{board.uri}/index.html"}
        )
    end

    blank = conn |> get("/search.php", %{"board" => first.uri}) |> html_response(200)
    assert blank =~ ~s(id="advanced-search")
    assert blank =~ ~s(class="search-console")
    refute blank =~ ~s(<div class="ban">)

    page =
      conn
      |> get("/search.php", %{"text" => "shared phrase", "scope" => "all"})
      |> html_response(200)

    assert page =~ "first marker"
    assert page =~ "second marker"
    assert page =~ "2 results"
    assert page =~ "across 2 boards"
  end

  test "advanced search uses the selected board's saved style", %{conn: conn} do
    board =
      board_fixture(%{uri: "style#{System.unique_integer([:positive, :monotonic])}"})

    page =
      conn
      |> put_req_cookie(
        "board_themes",
        Jason.encode!(%{board.uri => "tomorrow", "bant" => "yotsuba"})
      )
      |> get("/search.php", %{"board" => board.uri})
      |> html_response(200)

    {:ok, document} = Floki.parse_document(page)

    assert Floki.attribute(document, "link#stylesheet", "href")
           |> Enum.any?(&String.contains?(&1, "/stylesheets/tomorrow.css"))

    assert Floki.attribute(document, ~s(meta[name="eirinchan:board-name"]), "content") == [
             board.uri
           ]
  end

  test "advanced search applies the selected board's dark default before paint", %{conn: conn} do
    board =
      board_fixture(%{
        uri: "darkstyle#{System.unique_integer([:positive, :monotonic])}",
        config_overrides: %{default_theme: "yotsuba", default_theme_dark: "tomorrow"}
      })

    page =
      conn
      |> put_req_cookie("eirinchan_color_scheme", "dark")
      |> get("/search.php", %{"board" => board.uri})
      |> html_response(200)

    {:ok, document} = Floki.parse_document(page)

    assert Floki.attribute(document, "link#stylesheet", "href")
           |> Enum.any?(&String.contains?(&1, "/stylesheets/tomorrow.css"))

    assert Floki.attribute(document, "link#stylesheet", "data-auto-theme-dark-name") == [
             "tomorrow"
           ]
  end

  test "all-board search preserves the originating board's automatic dark style", %{conn: conn} do
    board =
      board_fixture(%{
        uri: "darkall#{System.unique_integer([:positive, :monotonic])}",
        config_overrides: %{default_theme: "yotsuba", default_theme_dark: "tomorrow"}
      })

    initial_page =
      conn
      |> put_req_cookie("eirinchan_color_scheme", "dark")
      |> get("/search.php", %{"board" => board.uri})
      |> html_response(200)

    {:ok, initial_document} = Floki.parse_document(initial_page)

    assert Floki.attribute(initial_document, ~s(input[name="theme_board"]), "value") == [
             board.uri
           ]

    results_page =
      build_conn()
      |> put_req_cookie("eirinchan_color_scheme", "dark")
      |> get("/search.php", %{
        "text" => "automatic dark style",
        "scope" => "all",
        "theme_board" => board.uri
      })
      |> html_response(200)

    {:ok, results_document} = Floki.parse_document(results_page)

    assert Floki.attribute(results_document, "link#stylesheet", "href")
           |> Enum.any?(&String.contains?(&1, "/stylesheets/tomorrow.css"))

    assert Floki.attribute(results_document, ~s(input[name="theme_board"]), "value") == [
             board.uri
           ]
  end

  test "advanced search applies stored identity, media, country, and date filters", %{conn: conn} do
    board = board_fixture(%{uri: "fields#{System.unique_integer([:positive, :monotonic])}"})

    {:ok, post, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{"body" => "advanced filter target", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    Repo.update_all(from(candidate in Eirinchan.Posts.Post, where: candidate.id == ^post.id),
      set: [
        tripcode: "!trip",
        email: "poster@example.test",
        poster_id: "ABC123",
        flag_codes: ["ca", "mokou", "thedoors", "thesmiths", "thrembo"],
        file_name: "sample.png",
        file_path: "/media/sample.png",
        file_md5: "kAFQmDzST7DWlj99KOF/cg==",
        image_width: 640,
        image_height: 480,
        spoiler: true,
        inserted_at: ~U[2026-04-15 12:00:00Z]
      ]
    )

    params = %{
      "text" => "advanced filter",
      "board" => board.uri,
      "tripcode" => "!trip",
      "email" => "poster@example.test",
      "uid" => "ABC123",
      "country" => "ca,mokou,thedoors,thesmiths,thrembo",
      "filename" => "sample.png",
      "image_hash" => "kAFQmDzST7DWlj99KOF/cg==",
      "width" => "640",
      "height" => "480",
      "start" => "2026-04-01",
      "end" => "2026-04-30",
      "image" => "spoiler"
    }

    page = conn |> get("/search.php", params) |> html_response(200)
    assert page =~ "advanced filter target"

    for flags <- [
          "canada,mokou,thedoors,thesmiths,thrembo",
          "ca",
          "canada"
        ] do
      alias_page =
        build_conn()
        |> get("/search.php", Map.put(params, "country", flags))
        |> html_response(200)

      assert alias_page =~ "advanced filter target"
    end

    no_match =
      build_conn()
      |> get("/search.php", Map.put(params, "country", "us"))
      |> html_response(200)

    assert no_match =~ "(No results.)"
  end

  test "advanced search rejects non-canonical image hashes before querying", %{conn: conn} do
    board = board_fixture(%{uri: "hash#{System.unique_integer([:positive, :monotonic])}"})

    page =
      conn
      |> get("/search.php", %{
        "board" => board.uri,
        "image_hash" => "not-a-base64-md5-value"
      })
      |> html_response(200)

    assert page =~ "Enter a search term or filter."

    {:ok, document} = Floki.parse_document(page)
    assert Floki.attribute(document, "#search-image-hash", "maxlength") == ["24"]
    assert Floki.attribute(document, "#search-image-file", "name") == []
  end

  test "advanced search paginates bounded results and groups matching posts by thread", %{
    conn: conn
  } do
    board =
      board_fixture(%{
        uri: "pages#{System.unique_integer([:positive, :monotonic])}",
        config_overrides: %{search_page_size: 1}
      })

    {:ok, thread, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{"body" => "pagination common older", "post" => "New Topic"},
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    {:ok, _reply, _meta} =
      Eirinchan.Posts.create_post(
        board,
        %{
          "thread" => Integer.to_string(PublicIds.public_id(thread)),
          "body" => "pagination common newer",
          "post" => "New Reply"
        },
        config: Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides),
        request: %{referer: "http://example.test/#{board.uri}/index.html"}
      )

    first_page =
      conn
      |> get("/search.php", %{"text" => "pagination common", "board" => board.uri})
      |> html_response(200)

    assert first_page =~ "pagination common newer"
    refute first_page =~ "pagination common older"
    assert first_page =~ "page=2"

    second_page =
      build_conn()
      |> get("/search.php", %{"text" => "pagination common", "board" => board.uri, "page" => "2"})
      |> html_response(200)

    assert second_page =~ "pagination common older"

    grouped =
      build_conn()
      |> get("/search.php", %{
        "text" => "pagination common",
        "board" => board.uri,
        "results" => "threads"
      })
      |> html_response(200)

    assert grouped =~ "1 result"
  end

  test "search statistics record filters and pseudonymous client dimensions", %{conn: _conn} do
    board = board_fixture(%{uri: "stats#{System.unique_integer([:positive, :monotonic])}"})

    conn =
      %{build_conn() | remote_ip: {198, 51, 100, 77}}
      |> put_req_header("user-agent", "Search Statistics Test Agent/1.0")

    conn
    |> get("/search.php", %{
      "board" => board.uri,
      "text" => "privacy marker",
      "subject" => "subject marker",
      "image" => "with",
      "results" => "threads",
      "highlight" => "1"
    })
    |> html_response(200)

    counters =
      Eirinchan.Statistics.drain_counters()
      |> Map.values()
      |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _key, left, right -> left + right end))

    assert counters["search.attempts"] == 1
    assert counters["search.features.text"] == 1
    assert counters["search.features.subject"] == 1
    assert counters["search.features.image_with"] == 1
    assert counters["search.features.results_threads"] == 1
    assert counters["search.features.highlight"] == 1
    assert counters["search.scope.single_board"] == 1
    assert counters["search.modes.image.with"] == 1

    assert Enum.any?(counters, fn {key, count} ->
             String.starts_with?(key, "search.clients.network.") and count == 1
           end)

    assert Enum.any?(counters, fn {key, count} ->
             String.starts_with?(key, "search.clients.user_agent.") and count == 1
           end)

    serialized = inspect(counters)
    refute serialized =~ "198.51.100.77"
    refute serialized =~ "Search Statistics Test Agent"
    refute serialized =~ "privacy marker"
  end
end
