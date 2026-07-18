defmodule Eirinchan.StatsTest do
  use Eirinchan.DataCase

  alias Eirinchan.AprilFoolsTeam
  alias Eirinchan.BrowserIdentities
  alias Eirinchan.BrowserIdentities.Identity
  alias Eirinchan.BrowserIdentity
  alias Eirinchan.BrowserPresence
  alias Eirinchan.Repo
  alias Eirinchan.Stats

  setup do
    :ets.delete_all_objects(:eirinchan_browser_presence)
    :ets.delete_all_objects(:eirinchan_browser_presence_dirty)
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

  test "threads_perhour excludes replies and respects the supplied snapshot time" do
    board = board_fixture()
    thread = thread_fixture(board)
    _reply = reply_fixture(board, thread)
    now = ~U[2026-07-18 12:00:00Z]

    Eirinchan.Repo.update_all(
      Ecto.Query.from(p in Eirinchan.Posts.Post, where: p.id in ^[thread.id]),
      set: [inserted_at: DateTime.add(now, -30 * 60, :second)]
    )

    old_thread = thread_fixture(board)

    Eirinchan.Repo.update_all(
      Ecto.Query.from(p in Eirinchan.Posts.Post, where: p.id == ^old_thread.id),
      set: [inserted_at: DateTime.add(now, -2 * 60 * 60, :second)]
    )

    assert Stats.threads_perhour(board, now: now) == 1
    assert Stats.threads_perhour(board.id, now: now) == 1
  end

  test "users_10minutes counts tracked browser presence" do
    first = identity_fixture()
    second = identity_fixture()

    BrowserPresence.touch(first.browser_ref)
    BrowserPresence.touch(second.browser_ref)

    assert Stats.users_10minutes() == 2
    assert Stats.active_browsers_10minutes() == 2
  end

  test "users_10minutes excludes crawler requests from tracked presence" do
    crawler = identity_fixture()
    human = identity_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> Map.put(:method, "GET")
      |> Map.put(:request_path, "/bant/")
      |> Plug.Conn.put_req_header(
        "user-agent",
        "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)"
      )
      |> Plug.Conn.assign(:browser_token, crawler.browser_ref)
      |> Plug.Conn.assign(:returning_browser_token, true)

    _ = EirinchanWeb.Plugs.TrackBrowserPresence.call(conn, [])
    BrowserPresence.touch(human.browser_ref)

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

    assert Stats.team_variable("team_2") ==
             {2, team.display_name, team.html_colour, team.post_count}

    assert Stats.team_variable("team_7") ==
             {7, futa.display_name, futa.html_colour, futa.post_count}

    assert Stats.team_variable("team_10") ==
             {10, limbus.display_name, limbus.html_colour, limbus.post_count}

    assert Stats.team_variable("team_11") ==
             {11, cobson.display_name, cobson.html_colour, cobson.post_count}

    assert Stats.team_variable("team_12") ==
             {12, haters.display_name, haters.html_colour, haters.post_count}

    assert Stats.team_variable("team_99") == nil
  end

  defp identity_fixture do
    now = DateTime.utc_now(:second)

    %Identity{}
    |> Identity.changeset(%{
      browser_ref: BrowserIdentity.generate_token() |> BrowserIdentity.reference(),
      issued_at: now,
      last_seen_at: now,
      expires_at: DateTime.add(now, BrowserIdentities.ttl_seconds(), :second)
    })
    |> Repo.insert!()
  end
end
