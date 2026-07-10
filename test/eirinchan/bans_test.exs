defmodule Eirinchan.BansTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.Bans

  test "creates and lists bans" do
    board = board_fixture()
    moderator = moderator_fixture()

    assert {:ok, ban} =
             Bans.create_ban(%{
               board_id: board.id,
               mod_user_id: moderator.id,
               ip_subnet: "203.0.113.4",
               reason: "Spam"
             })

    assert [%{id: ban_id, ip_subnet: "203.0.113.4", reason: "Spam"}] =
             Bans.list_bans(board_id: board.id)

    assert ban_id == ban.id
  end

  test "creates ban appeals for existing bans" do
    assert {:ok, ban} = Bans.create_ban(%{ip_subnet: "203.0.113.4", reason: "Spam"})
    assert {:ok, appeal} = Bans.create_appeal(ban.id, %{body: "Please review"})

    assert [%{id: appeal_id, body: "Please review", status: "open"}] = Bans.list_appeals()
    assert appeal_id == appeal.id
  end

  test "creates public ban appeals only for the matching banned ip" do
    board = board_fixture()

    assert {:ok, ban} =
             Bans.create_ban(%{board_id: board.id, ip_subnet: "203.0.113.0/24", reason: "Spam"})

    assert {:ok, appeal} =
             Bans.create_appeal_for_request(
               ban.id,
               %{appeal: "Please review"},
               board,
               {203, 0, 113, 9}
             )

    assert appeal.body == "Please review"

    assert {:error, :not_found} =
             Bans.create_appeal_for_request(
               ban.id,
               %{appeal: "Wrong user"},
               board,
               {198, 51, 100, 9}
             )
  end

  test "public ban appeals enforce vichan-style pending and length limits" do
    board = board_fixture()

    assert {:ok, ban} =
             Bans.create_ban(%{
               board_id: board.id,
               ip_subnet: "203.0.113.4",
               reason: "Short ban",
               expires_at: DateTime.add(DateTime.utc_now(), 60 * 60, :second)
             })

    assert {:error, :appeal_too_short} =
             Bans.create_appeal_for_request(
               ban.id,
               %{appeal: "Please review"},
               board,
               {203, 0, 113, 4}
             )

    assert {:ok, long_ban} =
             Bans.create_ban(%{
               board_id: board.id,
               ip_subnet: "198.51.100.4",
               reason: "Long ban",
               expires_at: DateTime.add(DateTime.utc_now(), 60 * 60 * 24, :second)
             })

    assert {:ok, _appeal} =
             Bans.create_appeal_for_request(
               long_ban.id,
               %{appeal: "Please review"},
               board,
               {198, 51, 100, 4}
             )

    assert {:error, :appeal_pending} =
             Bans.create_appeal_for_request(
               long_ban.id,
               %{appeal: "Second appeal"},
               board,
               {198, 51, 100, 4}
             )
  end

  test "finds active board bans for matching request ips and resolves appeals" do
    board = board_fixture()
    moderator = moderator_fixture()

    assert {:ok, ban} =
             Bans.create_ban(%{
               board_id: board.id,
               mod_user_id: moderator.id,
               ip_subnet: "203.0.113.0/24",
               reason: "Raid",
               expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
             })

    assert %{} = Bans.active_ban_for_request(board, {203, 0, 113, 44})

    assert {:ok, appeal} = Bans.create_appeal(ban.id, %{body: "Unban me"})

    assert {:ok, resolved} =
             Bans.resolve_appeal(appeal.id, %{status: "resolved", resolution_note: "Reviewed"})

    assert resolved.status == "resolved"
    assert resolved.resolution_note == "Reviewed"
    assert %{active: false} = Bans.get_ban(ban.id)
  end

  test "parses vichan-style ban lengths" do
    assert {:ok, expires_at} = Bans.parse_length("1h")
    assert DateTime.diff(expires_at, DateTime.utc_now(), :second) in 3598..3602

    assert {:ok, expires_at} = Bans.parse_length("2 days")
    assert DateTime.diff(expires_at, DateTime.utc_now(), :second) in 172_798..172_802
  end

  test "create_ban accepts vichan-style length input" do
    assert {:ok, ban} = Bans.create_ban(%{ip_subnet: "203.0.113.4", reason: "Spam", length: "1h"})
    assert %DateTime{} = ban.expires_at
    assert DateTime.diff(ban.expires_at, DateTime.utc_now(), :second) in 3598..3602
  end

  test "matches CIDR subnet bans generically" do
    board = board_fixture()

    assert {:ok, _ban} =
             Bans.create_ban(%{
               board_id: board.id,
               ip_subnet: "99.254.200.0/24",
               reason: "Subnet"
             })

    assert %{} = Bans.active_ban_for_request(board, {99, 254, 200, 1})
    assert Bans.active_ban_for_request(board, {99, 255, 0, 1}) == nil
  end
end
