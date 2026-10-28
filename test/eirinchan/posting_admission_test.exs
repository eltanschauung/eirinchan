defmodule Eirinchan.PostingAdmissionTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.Antispam.FloodEntry
  alias Eirinchan.Posts
  alias Eirinchan.Posts.{Persistence, Post}
  alias Eirinchan.Runtime.Config

  test "a successful internal post without an IP keeps the prior behavior" do
    board = board_fixture()

    config =
      Config.compose(nil, %{}, %{generation_strategy: "build_on_load"},
        request_host: "example.test"
      )

    assert {:ok, _post, _meta} =
             Posts.create_post(board, %{"body" => "internal post", "post" => "New Topic"},
               request: %{referer: "http://example.test/#{board.uri}/index.html"},
               config: config,
               repo: Repo
             )

    assert Repo.aggregate(from(e in FloodEntry, where: e.board_id == ^board.id), :count, :id) == 0
  end

  test "post insertion and its flood record are rolled back together on later failure" do
    board = board_fixture()

    config =
      Config.compose(nil, %{}, %{generation_strategy: "build_on_load"},
        request_host: "example.test"
      )

    attrs = %{"body" => "synthetic post", "ip_subnet" => "192.0.2.10"}
    request = %{remote_ip: {192, 0, 2, 10}}
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:error, :forced_failure} =
             Persistence.create_post_record(
               board,
               nil,
               attrs,
               request,
               Repo,
               config,
               now,
               false,
               fn -> {:error, :forced_failure} end
             )

    assert Repo.aggregate(from(p in Post, where: p.board_id == ^board.id), :count, :id) == 0
    assert Repo.aggregate(from(e in FloodEntry, where: e.board_id == ^board.id), :count, :id) == 0

    assert Repo.get!(Eirinchan.Boards.BoardRecord, board.id).next_public_post_id ==
             board.next_public_post_id
  end
end
