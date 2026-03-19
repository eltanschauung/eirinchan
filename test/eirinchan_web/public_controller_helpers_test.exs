defmodule EirinchanWeb.PublicControllerHelpersTest do
  use ExUnit.Case, async: true

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
             last_seen_post_id: 42
           }
  end
end
