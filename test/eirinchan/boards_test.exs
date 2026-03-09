defmodule Eirinchan.BoardsTest do
  use ExUnit.Case, async: true

  alias Eirinchan.Boards
  alias Eirinchan.Runtime

  test "open_board builds request-scoped board context with pre-board runtime paths" do
    context =
      Runtime.bootstrap(
        defaults: %{
          root: "/",
          board_path: "%s/",
          board_abbreviation: "/%s/",
          file_post: "post.php",
          file_index: "index.html",
          file_page: "%d.html",
          file_page50: "%d+50.html",
          file_page_slug: "%d-%s.html",
          file_page50_slug: "%d-%s+50.html",
          file_mod: "mod.php",
          file_script: "main.js",
          board_regex: "[a-z]+",
          dir: %{img: "img/", thumb: "thumb/", res: "res/"}
        },
        instance_overrides: %{root: "/boards/"},
        request_host: "example.test"
      )

    {:ok, opened} =
      Boards.open_board("tech",
        context: context,
        defaults: context.config,
        instance_overrides: %{root: "/boards/"},
        request_host: "example.test",
        board_store:
          {Eirinchan.Boards.MemoryStore,
           boards: %{
             "tech" => %{
               uri: "tech",
               title: "Technology",
               subtitle: "wired",
               config_overrides: %{board_path: "ignored/%s/"}
             }
           }}
      )

    assert opened.board.uri == "tech"
    assert opened.board.title == "Technology"
    assert opened.board.name == "Technology"
    assert opened.board.dir == "tech/"
    assert opened.board.url == "/tech/"
    assert opened.config.root == "/boards/"
    assert opened.config.uri_thumb == "/boards/tech/thumb/"
    assert opened.config.uri_img == "/boards/tech/img/"
  end

  test "open_board returns existing context when the same board is already loaded" do
    {:ok, context} =
      Boards.open_board("tech",
        defaults: %{root: "/", dir: %{img: "img/", thumb: "thumb/", res: "res/"}},
        board_store:
          {Eirinchan.Boards.MemoryStore,
           boards: %{"tech" => %{uri: "tech", title: "Technology", config_overrides: %{}}}}
      )

    assert {:ok, ^context} = Boards.open_board("tech", context: context)
  end

  test "open_board returns not_found for unknown boards" do
    assert {:error, :not_found} =
             Boards.open_board("missing",
               defaults: %{root: "/", dir: %{img: "img/", thumb: "thumb/", res: "res/"}},
               board_store: {Eirinchan.Boards.MemoryStore, boards: %{}}
             )
  end
end
