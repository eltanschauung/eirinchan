defmodule EirinchanWeb.ProxyRequestControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.{Antispam, Bans, Feedback, Posts, Repo}

  setup do
    previous = Application.get_env(:eirinchan, :proxy_request, %{})
    previous_feedback_store_ip = Application.get_env(:eirinchan, :feedback_store_ip, false)

    on_exit(fn ->
      Application.put_env(:eirinchan, :proxy_request, previous)
      Application.put_env(:eirinchan, :feedback_store_ip, previous_feedback_store_ip)
    end)

    :ok
  end

  test "trusted proxies supply the effective client ip for posting metadata", %{conn: conn} do
    Application.put_env(:eirinchan, :proxy_request, %{
      trust_headers: true,
      trusted_ips: ["203.0.113.10"]
    })

    board =
      board_fixture(%{
        config_overrides: %{
          country_flags: true,
          proxy_save: true,
          country_flag_data: %{"198.51.100.25" => %{code: "mx", name: "Mexico"}}
        }
      })

    conn =
      conn
      |> Map.put(:remote_ip, {203, 0, 113, 10})
      |> put_req_header("x-forwarded-for", "198.51.100.25, 203.0.113.10")
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "proxied post",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => thread_id} = json_response(conn, 200)

    {:ok, post} = Posts.get_post(board, thread_id)
    assert post.ip_subnet == "198.51.100.25"
    assert post.proxy == "198.51.100.25, 203.0.113.10"

    thread_page =
      conn
      |> recycle()
      |> get("/#{board.uri}/res/#{thread_id}.html")
      |> html_response(200)

    assert thread_page =~ ~s(title="Mexico")
  end

  test "untrusted proxies do not affect posting metadata", %{conn: conn} do
    Application.put_env(:eirinchan, :proxy_request, %{
      trust_headers: true,
      trusted_ips: ["203.0.113.10"]
    })

    board =
      board_fixture(%{
        config_overrides: %{
          country_flags: true,
          proxy_save: true,
          country_flag_data: %{"198.51.100.25" => %{code: "mx", name: "Mexico"}}
        }
      })

    conn =
      conn
      |> Map.put(:remote_ip, {198, 51, 100, 200})
      |> put_req_header("x-forwarded-for", "198.51.100.25")
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "direct post",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"id" => thread_id} = json_response(conn, 200)

    {:ok, post} = Posts.get_post(board, thread_id)
    assert post.ip_subnet == "198.51.100.200"
    assert is_nil(post.proxy)
  end

  test "trusted proxy client ips participate in ban checks and search logging", %{conn: conn} do
    Application.put_env(:eirinchan, :proxy_request, %{
      trust_headers: true,
      trusted_cidrs: ["203.0.113.0/24"]
    })

    board =
      board_fixture(%{
        uri: "proxy#{System.unique_integer([:positive])}",
        config_overrides: %{
          search_queries_per_minutes: [1, 1],
          search_queries_per_minutes_all: [0, 1]
        }
      })

    {:ok, _ban} =
      Bans.create_ban(%{
        board_id: board.id,
        ip_subnet: "198.51.100.44",
        reason: "Proxy tested ban"
      })

    banned_conn =
      conn
      |> Map.put(:remote_ip, {203, 0, 113, 44})
      |> put_req_header("x-forwarded-for", "198.51.100.44, 203.0.113.44")
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post(~p"/#{board.uri}/post", %{
        "body" => "should fail",
        "json_response" => "1",
        "post" => "New Topic"
      })

    assert %{"error" => "You are banned."} = json_response(banned_conn, 403)

    search_conn =
      build_conn()
      |> Map.put(:remote_ip, {203, 0, 113, 45})
      |> put_req_header("x-forwarded-for", "198.51.100.55, 203.0.113.45")
      |> get("/search.php", %{"q" => "proxied", "board" => board.uri})

    assert html_response(search_conn, 200) =~ "No results."

    assert Enum.any?(
             Antispam.list_public_activity_entries("198.51.100.55", repo: Repo),
             &(&1.activity == "search" and &1.board_id == board.id)
           )
  end

  test "trusted proxy client ips are used for feedback capture", %{conn: conn} do
    Application.put_env(:eirinchan, :proxy_request, %{
      trust_headers: true,
      trusted_ips: ["203.0.113.10"]
    })

    Application.put_env(:eirinchan, :feedback_store_ip, true)

    conn =
      conn
      |> Map.put(:remote_ip, {203, 0, 113, 10})
      |> put_req_header("x-forwarded-for", "192.168.5.25, 203.0.113.10")
      |> post("/feedback", %{
        "name" => "Anon",
        "body" => "proxied feedback",
        "json_response" => "1"
      })

    assert %{"feedback_id" => feedback_id, "status" => "ok"} = json_response(conn, 200)
    assert Feedback.get_feedback(feedback_id).ip_subnet == "192.168.0.0/16"
  end
end
