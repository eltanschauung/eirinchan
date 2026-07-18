defmodule Eirinchan.Statistics.RequestClassifierTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Eirinchan.Statistics.RequestClassifier

  test "separates full, hash, and body requests for a board catalog" do
    board = %{uri: "test"}

    full = classified_conn(EirinchanWeb.BoardController, :catalog, %{}, board)
    hash = classified_conn(EirinchanWeb.BoardController, :catalog, %{"fragment" => "md5"}, board)
    body = classified_conn(EirinchanWeb.BoardController, :catalog, %{"fragment" => "1"}, board)

    assert "requests.board.test.catalog.full" in RequestClassifier.metrics(full)
    assert "requests.board.test.catalog.fragment_hash" in RequestClassifier.metrics(hash)
    assert "requests.board.test.catalog.fragment_body" in RequestClassifier.metrics(body)
  end

  test "counts bounded public actions and rate-limit outcomes" do
    conn =
      classified_conn(
        EirinchanWeb.SearchController,
        :show,
        %{"search" => "bounded terms", "board" => "test"}
      )
      |> put_private(:statistics_rate_limit, "search")

    metrics = RequestClassifier.metrics(conn)

    assert "actions.search.attempted" in metrics
    assert "actions.search.rate_limited" in metrics
    assert "rate_limits.search" in metrics
    assert "rate_limits.total" in metrics
  end

  test "does not turn arbitrary board parameters into metric keys" do
    conn =
      classified_conn(
        EirinchanWeb.SearchController,
        :show,
        %{"search" => "query", "board" => String.duplicate("x", 1_000)}
      )

    metrics = RequestClassifier.metrics(conn)

    assert "actions.search.attempted" in metrics
    refute Enum.any?(metrics, &String.contains?(&1, String.duplicate("x", 65)))
  end

  defp classified_conn(controller, action, params, board \\ nil) do
    conn =
      :get
      |> conn("/")
      |> Map.put(:params, params)
      |> Map.put(:status, 200)
      |> put_private(:phoenix_controller, controller)
      |> put_private(:phoenix_action, action)

    if board, do: assign(conn, :current_board, board), else: conn
  end
end
