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
      |> Ecto.Changeset.change(display_name: "Finasteride 💊", html_colour: "#ADD8E6", post_count: 200)
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
      |> Ecto.Changeset.change(display_name: "Yukari Whale 🐋", html_colour: "#FFFF00", post_count: 11)
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
