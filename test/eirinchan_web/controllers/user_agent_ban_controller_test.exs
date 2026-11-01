defmodule EirinchanWeb.UserAgentBanControllerTest do
  use EirinchanWeb.ConnCase, async: false
  import Ecto.Query
  alias Eirinchan.{Bans, Posts, Repo}

  test "post ban options default to its recorded agent and allow IP-only bans", %{conn: conn} do
    moderator = moderator_fixture(%{role: "admin"})
    board = board_fixture()
    post = thread_fixture(board)

    Repo.update_all(from(p in Posts.Post, where: p.id == ^post.id),
      set: [user_agent: "Synthetic/1", ip_subnet: "192.0.2.20"]
    )

    path = "/manage/boards/#{board.uri}/posts/#{post.public_id}/ban/browser"
    page = conn |> login_moderator(moderator) |> get(path) |> html_response(200)
    assert page =~ ~s(name="user_agent")
    assert page =~ ~s(value="Synthetic/1")

    result =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> post(path, %{"board" => "*", "reason" => "test"})

    assert redirected_to(result)
    assert [%{user_agent: "Synthetic/1"}] = Bans.list_bans()

    result =
      conn
      |> recycle()
      |> login_moderator(moderator)
      |> post(path, %{"board" => "*", "reason" => "test", "user_agent" => ""})

    assert redirected_to(result)
    assert Enum.any?(Bans.list_bans(), &is_nil(&1.user_agent))
  end

  test "a User-Agent match on another IP gets the ordinary ban response", %{conn: conn} do
    board = board_fixture()

    assert {:ok, _} =
             Bans.create_ban(%{
               board_id: board.id,
               ip_subnet: "192.0.2.20",
               user_agent: "Synthetic/1",
               reason: "test"
             })

    result =
      %{conn | remote_ip: {198, 51, 100, 20}}
      |> put_req_header("user-agent", "Synthetic/1")
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "body" => "Post",
        "post" => "New Topic",
        "json_response" => "1"
      })

    assert %{
             "error_code" => "banned",
             "banned" => true,
             "ban_id" => _,
             "appeal_available" => true
           } = json_response(result, 403)

    refute result.resp_body =~ "Synthetic/1"
    refute result.resp_body =~ "User-Agent"
  end

  test "the upload wait response has the exact requested text and a classic external alert", %{
    conn: conn
  } do
    board = board_fixture(%{config_overrides: %{ipaccess_time: 3}})
    message = "You've been authenticated for under 3 hours; image uploads disabled."

    result =
      conn
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "body" => "Image",
        "file" => upload_fixture("new.png"),
        "post" => "New Topic",
        "json_response" => "1"
      })

    assert %{"error_code" => "ipaccess_time", "error" => ^message} = json_response(result, 403)

    page =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/#{board.uri}/index.html")
      |> post("/#{board.uri}/post", %{
        "body" => "Image",
        "file" => upload_fixture("new.png"),
        "post" => "New Topic"
      })
      |> html_response(403)

    assert page =~ "data-upload-wait-message="
    assert page =~ "/js/upload-wait.js"
  end
end
