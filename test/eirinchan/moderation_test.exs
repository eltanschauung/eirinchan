defmodule Eirinchan.ModerationTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.Moderation

  test "create_user stores a hashed password and authenticate verifies it" do
    assert {:ok, moderator} =
             Moderation.create_user(%{
               username: "admin",
               password: "correct horse battery staple",
               role: "admin"
             })

    assert moderator.password_hash
    assert moderator.password_salt == "argon2id:v1"
    assert moderator.password_hash =~ "$argon2id$"
    refute moderator.password_hash == "correct horse battery staple"

    assert {:ok, authenticated} = Moderation.authenticate("admin", "correct horse battery staple")
    assert authenticated.id == moderator.id
    assert {:error, :invalid_credentials} = Moderation.authenticate("admin", "wrong")
  end

  test "authenticate accepts imported vichan passwords and upgrades them" do
    {legacy_hash, 0} =
      System.cmd("mkpasswd", ["--method=sha-512", "--rounds", "25000", "--salt", "testsalt", "secret123"])

    {:ok, user} =
      %Eirinchan.Moderation.ModUser{}
      |> Ecto.Changeset.change(%{
        username: "legacy_admin",
        password_hash: String.trim(legacy_hash),
        password_salt: "legacy:vichan:1",
        role: "admin"
      })
      |> Repo.insert()

    assert {:ok, authenticated} = Moderation.authenticate("legacy_admin", "secret123")
    assert authenticated.id == user.id

    upgraded = Repo.get!(Eirinchan.Moderation.ModUser, user.id)
    refute Eirinchan.Moderation.ModUser.legacy_vichan_password?(upgraded)
    assert Eirinchan.Moderation.ModUser.verify_password(upgraded, "secret123")
    assert upgraded.password_hash =~ "$argon2id$"
    assert upgraded.password_salt == "argon2id:v1"
  end

  test "authenticate upgrades the previous salted sha256 format" do
    salt = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    password = "legacy password is still accepted"

    hash =
      :crypto.hash(:sha256, salt <> password)
      |> Base.encode16(case: :lower)

    {:ok, user} =
      %Eirinchan.Moderation.ModUser{}
      |> Ecto.Changeset.change(%{
        username: "sha_admin",
        password_hash: hash,
        password_salt: salt,
        role: "admin"
      })
      |> Repo.insert()

    assert {:ok, _authenticated} = Moderation.authenticate(user.username, password)

    upgraded = Repo.get!(Eirinchan.Moderation.ModUser, user.id)
    assert upgraded.password_hash =~ "$argon2id$"
    assert upgraded.password_salt == "argon2id:v1"
    assert Eirinchan.Moderation.ModUser.verify_password(upgraded, password)
  end

  test "new moderator passwords must be at least twelve characters" do
    assert {:error, changeset} =
             Moderation.create_user(%{
               username: "too_short",
               password: "short",
               role: "admin"
             })

    assert {"should be at least %{count} character(s)", _opts} = changeset.errors[:password]
  end

  test "board access is grant-based for non-admin moderators" do
    board = board_fixture()
    other_board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"})
    admin = moderator_fixture(%{role: "admin"})

    refute Moderation.board_access?(moderator, board)
    assert Moderation.board_access?(admin, board)

    assert {:ok, _access} = Moderation.grant_board_access(moderator, board)

    assert Moderation.board_access?(moderator, board)
    refute Moderation.board_access?(moderator, other_board)
    assert Enum.map(Moderation.list_accessible_boards(moderator), & &1.id) == [board.id]
  end

  test "all_boards grants non-admin moderators access to every board" do
    board = board_fixture()
    other_board = board_fixture()

    assert {:ok, moderator} =
             Moderation.create_user(%{
               username: "globalmod",
               password: "correct horse battery staple",
               role: "mod",
               all_boards: true
             })

    assert Moderation.board_access?(moderator, board)
    assert Moderation.board_access?(moderator, other_board)

    accessible_board_ids = Enum.map(Moderation.list_accessible_boards(moderator), & &1.id)

    assert board.id in accessible_board_ids
    assert other_board.id in accessible_board_ids
  end

  test "ip notes and ip post history can be queried by moderators" do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"})

    thread =
      thread_fixture(board, %{
        body: "IP tracked body"
      })

    {:ok, _updated_thread} = Repo.update(Ecto.Changeset.change(thread, ip_subnet: "203.0.113.10"))

    assert {:ok, note} =
             Moderation.add_ip_note("203.0.113.10", %{
               body: "Known spammer",
               board_id: board.id,
               mod_user_id: moderator.id
             })

    assert [%{body: "Known spammer"}] =
             Moderation.list_ip_notes("203.0.113.10", board_id: board.id)

    assert [%{id: post_id, ip_subnet: "203.0.113.10"}] =
             Moderation.list_ip_posts("203.0.113.10", board_ids: [board.id])

    assert post_id == thread.id
    assert note.ip_subnet == "203.0.113.10"
  end

  test "ip notes can be updated and deleted" do
    board = board_fixture()
    moderator = moderator_fixture(%{role: "mod"})

    assert {:ok, note} =
             Moderation.add_ip_note("203.0.113.12", %{
               body: "Initial note",
               board_id: board.id,
               mod_user_id: moderator.id
             })

    assert {:ok, updated_note} = Moderation.update_ip_note(note, %{body: "Updated note"})
    assert updated_note.body == "Updated note"

    assert {:ok, _deleted_note} = Moderation.delete_ip_note(note.id)
    assert [] = Moderation.list_ip_notes("203.0.113.12", board_id: board.id)
  end
end
