defmodule EirinchanWeb.BuildManagementControllerTest do
  use EirinchanWeb.ConnCase, async: false

  alias Eirinchan.Build
  alias Eirinchan.BuildQueue
  alias Eirinchan.Posts
  alias Eirinchan.ThreadPaths
  alias Eirinchan.Runtime.Config

  test "rebuild route processes deferred build jobs for a board", %{conn: conn} do
    File.rm_rf!(Build.board_root())

    board = board_fixture(%{config_overrides: %{generation_strategy: "defer"}})
    moderator = moderator_fixture(%{role: "mod"}) |> grant_board_access_fixture(board)
    config = Config.compose(nil, %{}, board.config_overrides, request_host: "example.test")

    assert {:ok, thread, _meta} =
             Posts.create_post(
               board,
               %{
                 "body" => "Deferred body",
                 "subject" => "Deferred subject",
                 "post" => "New Topic"
               },
               config: config,
               request: %{referer: "http://example.test/#{board.uri}/index.html"}
             )

    board_dir = Path.join(Build.board_root(), board.uri)
    thread_path = Path.join([board_dir, config.dir.res, ThreadPaths.thread_filename(thread, config)])
    index_path = Path.join(board_dir, config.file_index)

    refute File.exists?(thread_path)
    refute File.exists?(index_path)
    assert Enum.map(BuildQueue.list_pending(), & &1.kind) == ["thread", "indexes"]

    rebuild_conn =
      conn
      |> login_moderator(moderator)
      |> put_secure_manage_token()
      |> put_req_header("accept", "application/json")
      |> post("/manage/boards/#{board.uri}/rebuild")

    assert %{"data" => %{"processed" => 2, "strategy" => "defer"}} =
             json_response(rebuild_conn, 200)

    assert File.read!(thread_path) =~ "Deferred body"
    assert File.read!(index_path) =~ "Deferred subject"
  end
end
