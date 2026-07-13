defmodule Eirinchan.AntispamTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.Antispam
  alias Eirinchan.BrowserAbuse
  alias Eirinchan.BrowserIdentity

  test "search query entries are stored and rate-limited per ip and board" do
    board = board_fixture()
    request = %{remote_ip: {198, 51, 100, 44}}

    config = %{
      search_query_limit_window: 60,
      search_query_limit_count: 2,
      search_query_global_limit_window: 60,
      search_query_global_limit_count: 0
    }

    assert {:ok, _entry} =
             Antispam.log_search_query("tripcode", request, repo: Repo, board_id: board.id)

    refute Antispam.search_rate_limited?("tripcode", request, config,
             repo: Repo,
             board_id: board.id
           )

    assert {:ok, _entry} =
             Antispam.log_search_query("tripcode", request, repo: Repo, board_id: board.id)

    assert Antispam.search_rate_limited?("tripcode", request, config,
             repo: Repo,
             board_id: board.id
           )

    assert [%{query: "tripcode"}, %{query: "tripcode"}] =
             Antispam.list_search_queries("198.51.100.44", repo: Repo)
  end

  test "search queries can be rate-limited globally per board" do
    board = board_fixture()

    config = %{
      search_query_limit_window: 60,
      search_query_limit_count: 0,
      search_query_global_limit_window: 60,
      search_query_global_limit_count: 2
    }

    assert {:ok, _entry} =
             Antispam.log_search_query("tripcode", %{remote_ip: {198, 51, 100, 44}},
               repo: Repo,
               board_id: board.id
             )

    refute Antispam.search_rate_limited?("tripcode", %{remote_ip: {198, 51, 100, 55}}, config,
             repo: Repo,
             board_id: board.id
           )

    assert {:ok, _entry} =
             Antispam.log_search_query("tripcode", %{remote_ip: {198, 51, 100, 45}},
               repo: Repo,
               board_id: board.id
             )

    assert Antispam.search_rate_limited?("tripcode", %{remote_ip: {198, 51, 100, 56}}, config,
             repo: Repo,
             board_id: board.id
           )
  end

  test "public actions reuse the flood table rate limits" do
    board =
      board_fixture(%{
        config_overrides: %{flood_time: 60, flood_time_ip: 60, flood_time_same: 60}
      })

    request = %{remote_ip: {198, 51, 100, 44}}
    runtime_board = Eirinchan.Boards.BoardRecord.to_board(board)

    config =
      Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides || %{},
        board: runtime_board
      )

    attrs = %{"report_post_id" => "123", "reason" => "spam"}

    refute match?(
             {:error, _},
             Antispam.check_public_action(board, :report, attrs, request, config, repo: Repo)
           )

    assert {:ok, _entry} =
             Antispam.log_public_action(board, :report, attrs, request, repo: Repo)

    assert {:error, :antispam} =
             Antispam.check_public_action(board, :report, attrs, request, config, repo: Repo)
  end

  test "search limits enforce browser, IP-browser pair, and global dimensions independently" do
    browser_ref = BrowserIdentity.reference("browser-a")
    first = %{remote_ip: {198, 51, 100, 44}, browser_ref: browser_ref}
    other_ip = %{remote_ip: {198, 51, 100, 45}, browser_ref: browser_ref}

    assert {:ok, entry} = Antispam.log_search_query("feedback", first, repo: Repo)
    assert entry.browser_ref == browser_ref
    assert is_binary(entry.client_key)
    refute String.contains?(entry.client_key, "198.51.100.44")

    assert Antispam.public_search_rate_limited?(other_ip,
             repo: Repo,
             query: "feedback",
             per_ip_count: 0,
             per_browser_count: 1,
             per_client_count: 0,
             global_count: 0
           )

    assert BrowserAbuse.signaled?(other_ip, repo: Repo)

    refute Antispam.public_search_rate_limited?(other_ip,
             repo: Repo,
             query: "feedback",
             per_ip_count: 0,
             per_browser_count: 0,
             per_client_count: 1,
             global_count: 0
           )

    assert Antispam.public_search_rate_limited?(first,
             repo: Repo,
             query: "feedback",
             per_ip_count: 0,
             per_browser_count: 0,
             per_client_count: 1,
             global_count: 0
           )

    assert Antispam.public_search_rate_limited?(other_ip,
             repo: Repo,
             query: "feedback",
             per_ip_count: 0,
             per_browser_count: 0,
             per_client_count: 0,
             global_count: 1
           )
  end

  test "post flood limits follow a browser across IP changes" do
    board = board_fixture()
    browser_ref = BrowserIdentity.reference("browser-posting")
    first = %{remote_ip: {198, 51, 100, 44}, browser_ref: browser_ref}
    other_ip = %{remote_ip: {198, 51, 100, 45}, browser_ref: browser_ref}
    config = flood_config(board, %{flood_time_browser: 60, flood_global_count: 0})

    assert {:ok, entry} = Antispam.log_post(board, %{"body" => "first"}, first, repo: Repo)
    assert entry.browser_ref == browser_ref

    assert {:error, :antispam} =
             Antispam.check_post(board, %{"body" => "second"}, other_ip, config, repo: Repo)

    assert BrowserAbuse.signaled?(other_ip, repo: Repo)
  end

  test "post flood limits enforce the combined client and global counters" do
    board = board_fixture()
    first = %{remote_ip: {198, 51, 100, 44}, browser_ref: BrowserIdentity.reference("one")}
    second = %{remote_ip: {198, 51, 100, 45}, browser_ref: BrowserIdentity.reference("two")}

    assert {:ok, _entry} = Antispam.log_post(board, %{"body" => "first"}, first, repo: Repo)

    client_config =
      flood_config(board, %{
        flood_time_client: 60,
        flood_client_count: 1,
        flood_global_count: 0
      })

    assert {:error, :antispam} =
             Antispam.check_post(board, %{"body" => "again"}, first, client_config, repo: Repo)

    global_config = flood_config(board, %{flood_global_count: 1, flood_global_window: 60})

    assert {:error, :antispam} =
             Antispam.check_post(board, %{"body" => "other"}, second, global_config, repo: Repo)
  end

  defp flood_config(board, overrides) do
    runtime_board = Eirinchan.Boards.BoardRecord.to_board(board)

    Eirinchan.Runtime.Config.compose(
      nil,
      %{},
      Map.merge(
        %{
          flood_time: 0,
          flood_time_browser: 0,
          flood_time_client: 0,
          flood_global_count: 0
        },
        overrides
      ),
      board: runtime_board
    )
  end
end
