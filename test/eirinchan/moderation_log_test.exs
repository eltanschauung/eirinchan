defmodule Eirinchan.ModerationLogTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.ModerationLog

  import Eirinchan.ModerationFixtures

  test "creates, filters, and orders moderation log entries" do
    alice = moderator_fixture(%{username: "alice"})
    bob = moderator_fixture(%{username: "bob"})

    {:ok, _} =
      ModerationLog.log_action(%{
        mod_user_id: alice.id,
        actor_ip: "198.51.100.10",
        board_uri: "bant",
        text: "Deleted post No. 1"
      })

    Process.sleep(5)

    {:ok, _} =
      ModerationLog.log_action(%{
        mod_user_id: bob.id,
        actor_ip: "198.51.100.11",
        board_uri: "qa",
        text: "Created board /qa/"
      })

    assert ModerationLog.count_entries() == 2
    assert ModerationLog.count_entries(username: "alice") == 1
    assert ModerationLog.count_entries(board_uri: "qa") == 1

    [latest, earliest] = ModerationLog.list_entries()
    assert latest.mod_user.username == "bob"
    assert earliest.mod_user.username == "alice"
  end
end
