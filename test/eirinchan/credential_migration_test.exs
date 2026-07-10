defmodule Eirinchan.CredentialMigrationTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.CredentialHash
  alias Eirinchan.CredentialMigration
  alias Eirinchan.IpAccessEntry
  alias Eirinchan.Posts.Post

  test "hashes legacy database credentials and is idempotent" do
    board = board_fixture()
    post = thread_fixture(board)

    Repo.update_all(
      from(stored_post in Post, where: stored_post.id == ^post.id),
      set: [password: "delete-me"]
    )

    Repo.insert!(%IpAccessEntry{
      ip: "198.51.100.7",
      password: "LetMeIn",
      granted_at: ~N[2026-07-10 12:00:00]
    })

    assert {:ok, %{posts: 1, ip_access_entries: 1, settings: 0}} =
             CredentialMigration.run(repo: Repo, migrate_settings: false)

    migrated_post = Repo.get!(Post, post.id)
    [access_entry] = Repo.all(IpAccessEntry)

    assert CredentialHash.verify("delete-me", migrated_post.password, :post_delete)
    assert CredentialHash.verify("letmein", access_entry.password, :ip_access)

    assert {:ok, %{posts: 0, ip_access_entries: 0, settings: 0}} =
             CredentialMigration.run(repo: Repo, migrate_settings: false)
  end
end
