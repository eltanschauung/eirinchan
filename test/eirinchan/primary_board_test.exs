defmodule Eirinchan.PrimaryBoardTest do
  use ExUnit.Case, async: true

  alias Eirinchan.PrimaryBoard
  alias Eirinchan.Runtime.Config

  test "defaults to the conventional random board URI" do
    assert PrimaryBoard.uri(%{}) == "b"
    assert PrimaryBoard.uri(%{"primary_board_uri" => " /tech/ "}) == "tech"
  end

  test "rejects malformed primary board URIs" do
    assert PrimaryBoard.uri(%{primary_board_uri: ""}) == "b"
    assert PrimaryBoard.uri(%{primary_board_uri: "../private"}) == "b"
    assert PrimaryBoard.uri(%{primary_board_uri: String.duplicate("a", 33)}) == "b"
  end

  test "resolves the configured board with deterministic fallbacks" do
    boards = [%{uri: "a"}, %{uri: "b"}]

    assert PrimaryBoard.find(boards, %{primary_board_uri: "b"}).uri == "b"
    assert PrimaryBoard.find(boards, %{primary_board_uri: "missing"}).uri == "a"
    assert PrimaryBoard.resolve([], %{primary_board_uri: "tech"}) == %{uri: "tech"}
  end

  test "runtime config normalizes primary board settings" do
    defaults = Config.compose()
    assert defaults.primary_board_uri == "b"
    refute defaults.show_public_page_banner
    assert defaults.show_catalog_subtitle

    configured =
      Config.compose(
        nil,
        %{
          "primaryBoardUri" => " /tech/ ",
          "showPublicPageBanner" => true,
          "showCatalogSubtitle" => false
        },
        %{}
      )

    assert configured.primary_board_uri == "tech"
    assert configured.show_public_page_banner
    refute configured.show_catalog_subtitle

    assert Config.compose(nil, %{primary_board_uri: "not/a/board"}, %{}).primary_board_uri == "b"
  end
end
