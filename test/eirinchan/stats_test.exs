defmodule Eirinchan.StatsTest do
  use Eirinchan.DataCase

  alias Eirinchan.AprilFoolsTeam
  alias Eirinchan.BrowserPresence
  alias Eirinchan.Repo
  alias Eirinchan.Stats

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
    :ok
  end

  test "posts_perhour counts posts from the past hour for a board" do
    board = board_fixture()
    thread = thread_fixture(board)

    recent_reply = reply_fixture(board, thread)
    old_reply = reply_fixture(board, thread)

    Eirinchan.Repo.update_all(
      Ecto.Query.from(p in Eirinchan.Posts.Post, where: p.id == ^old_reply.id),
      set: [inserted_at: DateTime.utc_now() |> DateTime.add(-2 * 60 * 60, :second)]
    )

    assert Stats.posts_perhour(board) == 2
    assert Stats.posts_perhour(board.id) == 2
    assert recent_reply.id != old_reply.id
  end

  test "users_10minutes counts tracked browser presence" do
    BrowserPresence.touch("token-1234567890123456")
    BrowserPresence.touch("token-abcdefghijklmnop")

    assert Stats.users_10minutes() == 2
  end

  test "users_10minutes excludes crawler requests from tracked presence" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.put_req_header("user-agent", "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)")
      |> Plug.Conn.assign(:browser_token, "token-1234567890123456")

    _ = EirinchanWeb.Plugs.TrackBrowserPresence.call(conn, [])
    BrowserPresence.touch("token-abcdefghijklmnop")

    assert Stats.users_10minutes() == 1
  end

  test "team_* helpers return the april fools team tuple" do
    team = Repo.get!(AprilFoolsTeam, 2)
    futa = Repo.get!(AprilFoolsTeam, 7)
    limbus = Repo.get!(AprilFoolsTeam, 10)
    cobson = Repo.get!(AprilFoolsTeam, 11)
    haters = Repo.get!(AprilFoolsTeam, 12)

    assert Stats.team_2() == {2, team.display_name, team.html_colour, team.post_count}
    assert Stats.team_7() == {7, futa.display_name, futa.html_colour, futa.post_count}
    assert Stats.team_10() == {10, limbus.display_name, limbus.html_colour, limbus.post_count}
    assert Stats.team_11() == {11, cobson.display_name, cobson.html_colour, cobson.post_count}
    assert Stats.team_12() == {12, haters.display_name, haters.html_colour, haters.post_count}
    assert Stats.team_variable("team_2") == {2, team.display_name, team.html_colour, team.post_count}
    assert Stats.team_variable("team_7") == {7, futa.display_name, futa.html_colour, futa.post_count}
    assert Stats.team_variable("team_10") == {10, limbus.display_name, limbus.html_colour, limbus.post_count}
    assert Stats.team_variable("team_11") == {11, cobson.display_name, cobson.html_colour, cobson.post_count}
    assert Stats.team_variable("team_12") == {12, haters.display_name, haters.html_colour, haters.post_count}
    assert Stats.team_variable("team_99") == nil
  end
end
