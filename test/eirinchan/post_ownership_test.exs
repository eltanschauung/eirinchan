defmodule Eirinchan.PostOwnershipTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.BrowserIdentity
  alias Eirinchan.PostOwnership

  test "stores only an HMAC reference and accepts the original token for lookups" do
    board = Eirinchan.BoardsFixtures.board_fixture()
    post = Eirinchan.PostsFixtures.thread_fixture(board)
    token = "legacy-browser-token-for-storage"

    assert {:ok, ownership} = PostOwnership.record(token, post.id)
    assert ownership.browser_token == BrowserIdentity.reference(token)
    refute String.contains?(ownership.browser_token, token)
    assert PostOwnership.owned_post_ids(token, [post.id]) == MapSet.new([post.id])
  end
end
