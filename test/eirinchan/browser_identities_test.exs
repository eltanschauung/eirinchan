defmodule Eirinchan.BrowserIdentitiesTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.BrowserIdentities
  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.PostOwnership
  alias Eirinchan.Repo
  alias Eirinchan.ThreadWatcher

  test "registers an absolute server-side expiration and rotates the signed envelope" do
    token = BrowserIdentity.generate_token()
    now = ~U[2026-07-13 12:00:00Z]
    issued_at = DateTime.to_unix(now) - BrowserIdentities.rotation_seconds()

    assert {:ok, reference, rotate_cookie?: true} =
             BrowserIdentities.resolve(token, issued_at, repo: Repo, now: now)

    identity = Repo.get!(Identity, reference)
    assert identity.issued_at == DateTime.from_unix!(issued_at)

    assert identity.expires_at ==
             DateTime.add(identity.issued_at, BrowserIdentities.ttl_seconds(), :second)
  end

  test "expires the identity and deletes associated ownership and watches" do
    token = BrowserIdentity.generate_token()
    now = ~U[2026-07-13 12:00:00Z]
    issued_at = DateTime.to_unix(now)

    assert {:ok, reference, rotate_cookie?: false} =
             BrowserIdentities.resolve(token, issued_at, repo: Repo, now: now)

    board = Eirinchan.BoardsFixtures.board_fixture()
    post = Eirinchan.PostsFixtures.thread_fixture(board)
    assert {:ok, _ownership} = PostOwnership.record(token, post.id)
    assert {:ok, _watch} = ThreadWatcher.watch_thread(token, board.uri, post.id)

    expired_at = DateTime.add(now, BrowserIdentities.ttl_seconds() + 1, :second)

    assert {:expired, ^reference} =
             BrowserIdentities.resolve(token, issued_at, repo: Repo, now: expired_at)

    assert Repo.get(Identity, reference) == nil
    assert PostOwnership.owned_post_ids(token, [post.id]) == MapSet.new()
    refute ThreadWatcher.watched?(token, board.uri, post.id)
  end
end
