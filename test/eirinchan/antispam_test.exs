defmodule Eirinchan.AntispamTest do
  use Eirinchan.DataCase, async: true

  alias Eirinchan.Antispam

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
    board = board_fixture(%{config_overrides: %{flood_time: 60, flood_time_ip: 60, flood_time_same: 60}})
    request = %{remote_ip: {198, 51, 100, 44}}
    runtime_board = Eirinchan.Boards.BoardRecord.to_board(board)
    config = Eirinchan.Runtime.Config.compose(nil, %{}, board.config_overrides || %{}, board: runtime_board)
    attrs = %{"report_post_id" => "123", "reason" => "spam"}

    refute match?({:error, _}, Antispam.check_public_action(board, :report, attrs, request, config, repo: Repo))

    assert {:ok, _entry} =
             Antispam.log_public_action(board, :report, attrs, request, repo: Repo)

    assert {:error, :antispam} =
             Antispam.check_public_action(board, :report, attrs, request, config, repo: Repo)
  end
end
