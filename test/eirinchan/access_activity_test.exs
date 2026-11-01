defmodule Eirinchan.AccessActivityTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.{
    AccessList,
    CredentialHash,
    CredentialMigration,
    IpAccessEntry,
    Posts,
    PostAuthContext
  }

  alias Eirinchan.Runtime.Config

  test "duplicate authentication preserves age/count and adds up to ten distinct user agents" do
    old = DateTime.add(DateTime.utc_now(), -3600, :second)

    assert {:ok, first} =
             AccessList.record_access("192.0.2.0/24", "Door", now: old, user_agent: "Synthetic/1")

    Repo.update_all(IpAccessEntry, set: [post_count: 4])

    for n <- 1..15 do
      assert {:ok, repeated} =
               AccessList.record_access("192.0.2.0/24", "door", user_agent: "Synthetic/#{n}")

      assert repeated.authenticated_at == first.authenticated_at
      assert repeated.post_count == 4
      assert repeated.password == "Door"
    end

    entry = Repo.one!(IpAccessEntry)
    assert length(entry.user_agents) == 10
    assert Enum.uniq(entry.user_agents) == entry.user_agents
  end

  test "changing the password starts a fresh grant without inserting a second network row" do
    assert {:ok, first} =
             AccessList.record_access("192.0.2.0/24", "old",
               now: DateTime.add(DateTime.utc_now(), -3600, :second)
             )

    assert {:ok, updated} =
             AccessList.record_access("192.0.2.0/24", "new", user_agent: "Synthetic/2")

    assert DateTime.compare(updated.authenticated_at, first.authenticated_at) == :gt
    assert updated.post_count == 0
    assert Repo.aggregate(IpAccessEntry, :count) == 1
  end

  test "successful posts increment the associated grant and capture private authentication evidence" do
    board = board_fixture()
    config = Config.compose(nil, %{}, %{generation_strategy: "build_on_load"})
    assert {:ok, _} = AccessList.record_access("192.0.2.0/24", "synthetic-door")

    request = %{
      remote_ip: {192, 0, 2, 25},
      user_agent: "Synthetic/1",
      country_code: "GB",
      referer: "http://example.test/#{board.uri}/index.html"
    }

    assert {:ok, post, _} =
             Posts.create_public_post(
               board,
               %{"body" => "Actual post", "post" => "New Topic", "user_agent" => "Forged/2"},
               config: config,
               request: request
             )

    assert Repo.one!(IpAccessEntry).post_count == 1
    assert post.user_agent == "Synthetic/1"
    snapshot = Repo.get!(PostAuthContext, post.id)
    assert snapshot.auth_password == "synthetic-door"
    assert snapshot.country_code == "gb"
    assert snapshot.auth_age_seconds >= 0

    public =
      Eirinchan.Api.thread_json(
        %{
          thread: post,
          replies: [],
          reply_count: 0,
          image_count: 0,
          omitted_posts: 0,
          omitted_images: 0,
          last_modified: post.inserted_at
        },
        config
      )
      |> Jason.encode!()

    refute public =~ "synthetic-door"
    refute public =~ "Synthetic/1"
    refute public =~ "auth_password"

    assert {:error, _} =
             Posts.create_public_post(board, %{"body" => "", "post" => "New Topic"},
               config: config,
               request: request
             )

    assert Repo.one!(IpAccessEntry).post_count == 1
  end

  test "unused grants expire after twelve hours, with a tracking grace period for existing rows" do
    now = DateTime.utc_now()
    old = DateTime.add(now, -13 * 3600, :second)
    assert {:ok, unused} = AccessList.record_access("192.0.2.0/24", "door", now: old)
    assert {:ok, active} = AccessList.record_access("198.51.100.0/24", "door", now: old)
    Repo.update_all(from(e in IpAccessEntry, where: e.ip == ^active.ip), set: [post_count: 1])
    assert {:ok, grace} = AccessList.record_access("203.0.113.0/24", "door", now: old)

    Repo.update_all(from(e in IpAccessEntry, where: e.ip == ^grace.ip),
      set: [tracking_started_at: now]
    )

    assert {1, _} = AccessList.prune_unused(now: now)
    refute Repo.get(IpAccessEntry, unused.ip)
    assert Repo.get(IpAccessEntry, active.ip)
    assert Repo.get(IpAccessEntry, grace.ip)
  end

  test "posting rollback also rolls back its grant counter and private evidence" do
    board = board_fixture()
    assert {:ok, _} = AccessList.record_access("192.0.2.0/24", "synthetic-door")
    config = Config.compose(nil, %{}, %{generation_strategy: "build_on_load"})
    attrs = %{"body" => "Synthetic rollback", "post" => "New Topic", "ip_subnet" => "192.0.2.1"}
    request = %{remote_ip: {192, 0, 2, 1}}

    assert {:error, :synthetic_failure} =
             Eirinchan.Posts.Persistence.create_post_record(
               board,
               nil,
               attrs,
               request,
               Repo,
               config,
               DateTime.utc_now(),
               false,
               fn -> {:error, :synthetic_failure} end
             )

    assert Repo.one!(IpAccessEntry).post_count == 0
    assert Repo.aggregate(PostAuthContext, :count) == 0
    assert Repo.aggregate(Eirinchan.Posts.Post, :count) == 0
  end

  test "UTC grant checks and legacy conversion work in a non-UTC database session" do
    Repo.query!("SET LOCAL TIME ZONE 'America/New_York'")
    now = DateTime.utc_now()
    old = DateTime.add(now, -3 * 3600 - 30, :second)
    assert {:ok, entry} = AccessList.record_access("192.0.2.0/24", "door", now: old)
    assert AccessList.authentication_age_seconds({192, 0, 2, 1}) in 10830..10835
    assert "192.0.2.0/24" in AccessList.stored_entries()
    # Exercise the same conversion used by the upgrade, including a DST date.
    %{rows: [[utc]]} =
      Repo.query!(
        "SELECT ($1::timestamp AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'UTC'",
        [~N[2026-07-01 12:00:00]]
      )

    assert NaiveDateTime.compare(utc, ~N[2026-07-01 16:00:00]) == :eq

    %{rows: [[legacy_local]]} =
      Repo.query!("SELECT LOCALTIMESTAMP - INTERVAL '3 hours 30 seconds'")

    Repo.update_all(from(e in IpAccessEntry, where: e.ip == ^entry.ip),
      set: [authenticated_at: nil, granted_at: NaiveDateTime.truncate(legacy_local, :second)]
    )

    assert AccessList.authentication_age_seconds({192, 0, 2, 1}) in 10830..10835
  end

  test "historical evidence never attributes a newer grant to an older post" do
    board = board_fixture()
    post = thread_fixture(board)

    post =
      post
      |> Ecto.Changeset.change(
        ip_subnet: "192.0.2.1",
        inserted_at:
          DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

    assert {:ok, _} = AccessList.record_access("192.0.2.0/24", "newer-door")
    evidence = AccessList.evidence_for_post(post, Config.compose(nil, %{}, %{}))
    assert evidence.auth_password == nil
    assert evidence.authenticated_at == nil
  end

  test "known legacy hashes are recovered privately; unknown values are cleared without revoking grants" do
    Repo.insert!(%IpAccessEntry{
      ip: "192.0.2.0/24",
      password: CredentialHash.hash("known", :ip_access),
      granted_at: NaiveDateTime.local_now()
    })

    Repo.insert!(%IpAccessEntry{
      ip: "198.51.100.0/24",
      password: CredentialHash.hash("not-in-config", :ip_access),
      granted_at: NaiveDateTime.local_now()
    })

    assert CredentialMigration.restore_ip_access_passwords(passwords: ["known"]) == 2
    assert Repo.get!(IpAccessEntry, "192.0.2.0/24").password == "known"
    assert Repo.get!(IpAccessEntry, "198.51.100.0/24").password == nil
    assert Repo.aggregate(IpAccessEntry, :count) == 2
    assert CredentialMigration.restore_ip_access_passwords(passwords: ["known"]) == 0
  end
end
