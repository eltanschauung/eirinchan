defmodule Eirinchan.UserAgentBansTest do
  use Eirinchan.DataCase, async: false
  alias Eirinchan.{Bans, Posts, AccessList}
  alias Eirinchan.Runtime.Config

  test "IP or exact nonempty User-Agent independently enforces a ban in its board scope" do
    board = board_fixture()

    assert {:ok, ban} =
             Bans.create_ban(%{
               board_id: board.id,
               ip_subnet: "192.0.2.0/24",
               user_agent: "Synthetic/1"
             })

    assert Bans.active_ban_for_request(board, "198.51.100.10", user_agent: "Synthetic/1").id ==
             ban.id

    assert Bans.active_ban_for_request(board, "192.0.2.55", user_agent: "Different/2").id ==
             ban.id

    for agent <- [nil, "", "Synthetic/1 extra", "synthetic/1"] do
      refute Bans.active_ban_for_request(board, "198.51.100.10", user_agent: agent)
    end

    other = board_fixture()
    refute Bans.active_ban_for_request(other, "198.51.100.10", user_agent: "Synthetic/1")
  end

  test "User-Agent-only and IP-only targets work; empty/malformed targets fail" do
    board = board_fixture()
    assert {:ok, ban} = Bans.create_ban(%{board_id: board.id, user_agent: "Synthetic/1"})

    assert Bans.active_ban_for_request(board, "203.0.113.5", user_agent: "Synthetic/1").id ==
             ban.id

    assert {:error, _} = Bans.create_ban(%{user_agent: ""})

    for agent <- ["bad\nheader", String.duplicate("x", 1025), <<255>>] do
      assert {:error, _} = Bans.create_ban(%{ip_subnet: "192.0.2.1", user_agent: agent})
    end

    assert {:ok, _} = Bans.update_ban(ban, %{ip_subnet: "192.0.2.1", user_agent: ""})
    refute Bans.active_ban_for_request(board, "203.0.113.5", user_agent: "Synthetic/1")
    assert Bans.active_ban_for_request(board, "192.0.2.1")
  end

  test "an expired newer ban cannot hide an older valid one, including appeals" do
    board = board_fixture()
    assert {:ok, valid} = Bans.create_ban(%{board_id: board.id, user_agent: "Synthetic/1"})

    assert {:ok, _} =
             Bans.create_ban(%{
               board_id: board.id,
               user_agent: "Synthetic/1",
               expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
             })

    assert Bans.active_ban_for_request(board, "192.0.2.1", user_agent: "Synthetic/1").id ==
             valid.id

    assert {:ok, _} =
             Bans.create_appeal_for_request(
               valid.id,
               %{body: "Synthetic appeal"},
               board,
               "198.51.100.1",
               user_agent: "Synthetic/1"
             )
  end

  test "B24 retains private authentication evidence and bans the recorded agent" do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "admin"})

    assert {:ok, _} =
             AccessList.record_access("192.0.2.0/24", "synthetic-password",
               now: DateTime.add(DateTime.utc_now(), -7200, :second)
             )

    config = Config.compose(nil, %{}, %{generation_strategy: "build_on_load"})

    assert {:ok, post, _} =
             Posts.create_public_post(board, %{"body" => "Synthetic post", "post" => "New Topic"},
               config: config,
               request: %{
                 remote_ip: {192, 0, 2, 20},
                 user_agent: "Synthetic/1",
                 country_code: "CA",
                 referer: "http://example.test/#{board.uri}/index.html"
               }
             )

    assert {:ok, _} = AccessList.record_access("192.0.2.0/24", "different-password")

    assert {:ok, %{ban: ban, event: event}} =
             Posts.ban_subnet_and_delete_files(board, post.public_id, moderator, config: config)

    assert ban.user_agent == "Synthetic/1"
    assert event.auth_password == "synthetic-password"
    assert event.country_code == "ca"
    # Posts have second precision, while the grant retains microseconds.
    assert event.auth_age_seconds >= 7199
    assert event.auth_age_at_ban_seconds >= event.auth_age_seconds
  end
end
