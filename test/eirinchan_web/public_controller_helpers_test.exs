defmodule EirinchanWeb.PublicControllerHelpersTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias EirinchanWeb.PublicControllerHelpers

  test "fragment options decode fragment requests" do
    assert PublicControllerHelpers.fragment_options(%{"fragment" => "1"}) ==
             [fragment?: true, fragment_md5?: false]

    assert PublicControllerHelpers.fragment_options(%{"fragment" => "md5"}) ==
             [fragment?: false, fragment_md5?: true]

    assert PublicControllerHelpers.fragment_options(%{}) ==
             [fragment?: false, fragment_md5?: false]
  end

  test "dynamic fragment stamp is stable for equivalent MapSets" do
    assigns_a = [
      own_post_ids: MapSet.new([3, 1, 2]),
      show_yous: true,
      thread_watch_state: %{123 => %{watched: true}},
      current_moderator: %{id: 5, role: "admin"},
      secure_manage_token: "token",
      mobile_client?: false
    ]

    assigns_b = Keyword.put(assigns_a, :own_post_ids, MapSet.new([2, 3, 1]))

    assert PublicControllerHelpers.dynamic_fragment_stamp(assigns_a, :thread_watch_state) ==
             PublicControllerHelpers.dynamic_fragment_stamp(assigns_b, :thread_watch_state)
  end

  test "moderator body class composes base and extra classes" do
    conn = %Plug.Conn{assigns: %{current_moderator: %{id: 1}}}

    assert PublicControllerHelpers.moderator_body_class(conn, "active-catalog",
             extra_classes: ["theme-catalog"]
           ) == "8chan vichan is-moderator theme-catalog active-catalog"
  end

  test "watcher helpers use fast empty defaults when browser token is absent" do
    conn = %Plug.Conn{assigns: %{}}

    assert PublicControllerHelpers.watcher_metrics(conn) == %{
             watcher_count: 0,
             watcher_unread_count: 0,
             watcher_you_count: 0
           }

    assert PublicControllerHelpers.thread_watch_state(conn, "bant") == %{}

    assert PublicControllerHelpers.thread_watch(conn, "bant", 42) == %{
             watched: false,
             unread_count: 0,
             you_unread_count: 0,
             last_seen_post_id: 42
           }
  end

  test "watcher helpers reuse a supplied snapshot" do
    snapshot = %{
      metrics: %{watcher_count: 2, watcher_unread_count: 3, watcher_you_count: 1},
      watch_state_by_board: %{
        "bant" => %{42 => %{watched: true, unread_count: 3, you_unread_count: 1}}
      },
      summaries: []
    }

    assert PublicControllerHelpers.watcher_metrics(snapshot).watcher_count == 2

    assert PublicControllerHelpers.thread_watch_state(snapshot, "bant") ==
             snapshot.watch_state_by_board["bant"]

    assert PublicControllerHelpers.thread_watch(snapshot, "bant", 42).watched

    assert PublicControllerHelpers.watcher_state_by_board(snapshot) ==
             snapshot.watch_state_by_board
  end

  test "logs only genuinely slow public pages" do
    config = %{log_system: %{type: "stderr"}}

    fast_output =
      capture_io(:stderr, fn ->
        started_at_us = System.monotonic_time(:microsecond)

        assert :ok =
                 PublicControllerHelpers.maybe_log_page_performance(
                   "board.index",
                   started_at_us,
                   %{board: "test"},
                   config
                 )
      end)

    assert fast_output == ""

    slow_output =
      capture_io(:stderr, fn ->
        started_at_us = System.monotonic_time(:microsecond) - 2_100_000

        assert :ok =
                 PublicControllerHelpers.maybe_log_page_performance(
                   "board.index",
                   started_at_us,
                   %{board: "test"},
                   config
                 )
      end)

    decoded = Jason.decode!(String.trim(slow_output))
    assert decoded["event"] == "page.performance"
    assert decoded["metadata"]["total_ms"] >= 2_100
  end
end
