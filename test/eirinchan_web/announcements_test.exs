defmodule EirinchanWeb.AnnouncementsTest do
  use Eirinchan.DataCase, async: false

  alias Eirinchan.AprilFoolsTeam
  alias Eirinchan.Repo
  alias Eirinchan.AprilFoolsTeams
  alias EirinchanWeb.Announcements
  alias EirinchanWeb.FragmentCache

  setup do
    FragmentCache.clear()
    :ok
  end

  test "global message resolves april fools team placeholders for name colour and post_count" do
    team =
      Repo.get!(AprilFoolsTeam, 6)
      |> Ecto.Changeset.change(
        display_name: "Finasteride 💊",
        html_colour: "#ADD8E6",
        post_count: 200
      )
      |> Repo.update!()

    html =
      Announcements.global_message_html(%{
        global_message:
          ~s(<span style="color:{stats.team_6.colour}">Team {stats.team_6.name}'s Score: {stats.team_6.post_count}</span>)
      })

    assert html =~ ~s(<span style="color:#ADD8E6">Team Finasteride 💊's Score: )
    assert html =~ ~r/('son|clitty|bald|whale)00/
    assert team.display_name == "Finasteride 💊"
  end

  test "global message also supports canonical team field names" do
    _team =
      Repo.get!(AprilFoolsTeam, 1)
      |> Ecto.Changeset.change(
        display_name: "Yukari Whale 🐋",
        html_colour: "#FFFF00",
        post_count: 11
      )
      |> Repo.update!()

    html =
      Announcements.global_message_html(%{
        global_message:
          "Name: {stats.team_1.display_name} Colour: {stats.team_1.html_colour} Count: {stats.team_1.post_count}"
      })

    assert html =~ "Name: Yukari Whale 🐋"
    assert html =~ "Colour: #FFFF00"
    assert html =~ "Count: 14881488"
  end

  test "global message resolves and normalizes the TF2 display placeholder" do
    message =
      Announcements.global_message(
        %{global_message: "TF2 playercount: {tf2_display}"},
        tf2_now: 1_000,
        tf2_fetcher: fn ->
          {:ok, %{"success" => true, "display" => "12 / 42", "player_count" => 12}}
        end
      )

    assert message == "TF2 playercount: 12/42"
  end

  test "TF2 conditional renders only its following line when players are online" do
    message =
      Announcements.global_message(
        %{
          global_message:
            "Free password: bantptized\\n{if tf2_display > 0}\\nTF2 playercount: {tf2_display}\\nAfter"
        },
        tf2_now: 2_000,
        tf2_fetcher: fn ->
          {:ok, %{"success" => true, "display" => "3 / 42", "player_count" => 3}}
        end
      )

    assert message == "Free password: bantptized\nTF2 playercount: 3/42\nAfter"
  end

  test "TF2 conditional can follow content on the preceding line and removes an offline line" do
    message =
      Announcements.global_message(
        %{
          global_message:
            "Visitors: {stats.users_10minutes}\\nPPH: {stats.posts_perhour}{if tf2_display > 0}\\nTF2 playercount: {tf2_display}"
        },
        tf2_now: 3_000,
        board_ids: [0],
        tf2_fetcher: fn ->
          {:ok, %{"success" => true, "display" => "0 / 42", "player_count" => 0}}
        end
      )

    assert message =~ ~r/^Visitors: \d+\nPPH: \d+$/
    refute message =~ "TF2 playercount"
    refute message =~ "{if"
  end

  test "TF2 conditional following content keeps both lines when players are online" do
    message =
      Announcements.global_message(
        %{
          global_message:
            "PPH: {stats.posts_perhour}{if tf2_display > 0}\nTF2 playercount: {tf2_display}"
        },
        tf2_now: 3_500,
        board_ids: [0],
        tf2_fetcher: fn ->
          {:ok, %{"success" => true, "display" => "4 / 42", "player_count" => 4}}
        end
      )

    assert message =~ ~r/^PPH: \d+\nTF2 playercount: 4\/42$/
  end

  test "malformed parenthesis conditional is not accepted" do
    message =
      Announcements.global_message(
        %{global_message: "{if tf2_display > 0)\nTF2 playercount: {tf2_display}"},
        tf2_now: 3_750,
        tf2_fetcher: fn ->
          {:ok, %{"success" => true, "display" => "4 / 42", "player_count" => 4}}
        end
      )

    assert message == "{if tf2_display > 0)\nTF2 playercount: 4/42"
  end

  test "TF2 placeholder fetch is cached and remote failures fail closed" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    fetcher = fn ->
      Agent.update(calls, &(&1 + 1))
      {:error, :offline}
    end

    config = %{
      global_message: "Before\n{if tf2_display > 0}\nTF2 playercount: {tf2_display}\nAfter"
    }

    assert Announcements.global_message(config, tf2_now: 4_000, tf2_fetcher: fetcher) ==
             "Before\nAfter"

    assert Announcements.global_message(config, tf2_now: 4_000, tf2_fetcher: fetcher) ==
             "Before\nAfter"

    assert Agent.get(calls, & &1) == 1
  end

  test "silly post count applies the requested replacements" do
    transformed = AprilFoolsTeams.silly_post_count("1236789")
    transformed_again = AprilFoolsTeams.silly_post_count("1236789")

    assert transformed =~ "1488"
    assert transformed =~ "33"
    assert transformed =~ "Ϫ"
    assert transformed =~ "∞"
    assert transformed =~ "⑨"
    assert transformed =~ ~r/('son|clitty|bald|whale)/
    assert transformed == transformed_again
  end
end
